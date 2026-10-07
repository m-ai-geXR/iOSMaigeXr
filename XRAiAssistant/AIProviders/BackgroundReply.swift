import UIKit

// MARK: - Overview
//
// A reply must arrive even if the user leaves the app mid-request. iOS
// suspends an app soon after it goes to the background, which ends any
// connection the app holds, and no ordinary connection survives that.
//
// So when the app goes to the background with a reply still coming, the same
// request is handed to a background URLSession. The system runs it outside the
// app, while the app is suspended or even closed, and hands back the finished
// reply. Background sessions cannot stream, so this copy asks for the whole
// reply at once. Whichever copy finishes first is shown; the other is dropped.

/// Builds the non-streaming request a provider needs, and reads its reply.
enum BackgroundReplyRequests {

    struct Inputs {
        let provider: String
        let model: String
        let systemPrompt: String
        let userMessage: String
        let apiKey: String
        let temperature: Double
        let topP: Double
        let effort: AIEffort
        let control: AIModelControl
        let maxOutputTokens: Int
    }

    /// The request for `inputs`, or nil if this provider has no background path.
    static func request(for inputs: Inputs) -> URLRequest? {
        switch inputs.provider {
        case "OpenAI":
            return openAICompatible(url: "https://api.openai.com/v1/chat/completions", inputs: inputs, openAIControl: true)
        case "xAI":
            return openAICompatible(url: "https://api.x.ai/v1/chat/completions", inputs: inputs, openAIControl: false)
        case "Together.ai":
            return openAICompatible(url: "https://api.together.xyz/v1/chat/completions", inputs: inputs, openAIControl: false)
        case LocalServerConfig.providerName:
            guard let url = LocalServerConfig.chatCompletionsURL(from: LocalServerConfig.baseURL) else { return nil }
            var local = openAICompatible(url: url.absoluteString, inputs: inputs, openAIControl: false)
            if let body = local?.httpBody,
               var json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] {
                json["model"] = LocalServerConfig.serverModelName(from: inputs.model)
                json.removeValue(forKey: "max_tokens")
                local?.httpBody = try? JSONSerialization.data(withJSONObject: json)
            }
            if inputs.apiKey.isEmpty || inputs.apiKey == "changeMe" {
                local?.setValue(nil, forHTTPHeaderField: "Authorization")
            }
            return local
        case "Anthropic":
            return anthropic(inputs)
        case "Google AI":
            return google(inputs)
        default:
            return nil
        }
    }

    /// The reply text in a finished response body, for the given provider.
    static func replyText(provider: String, data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        switch provider {
        case "Anthropic":
            let blocks = json["content"] as? [[String: Any]] ?? []
            let text = blocks.filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        case "Google AI":
            let candidates = json["candidates"] as? [[String: Any]] ?? []
            let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            let text = parts.filter { ($0["thought"] as? Bool) != true }
                .compactMap { $0["text"] as? String }.joined()
            return text.isEmpty ? nil : text
        default:
            let choices = json["choices"] as? [[String: Any]] ?? []
            let text = (choices.first?["message"] as? [String: Any])?["content"] as? String
            return (text?.isEmpty ?? true) ? nil : text
        }
    }

    // MARK: Builders

    private static func openAICompatible(url: String, inputs: Inputs, openAIControl: Bool) -> URLRequest? {
        guard let url = URL(string: url) else { return nil }
        var body: [String: Any] = [
            "model": inputs.model,
            "messages": [
                ["role": "system", "content": inputs.systemPrompt],
                ["role": "user", "content": inputs.userMessage]
            ],
            "stream": false
        ]
        if openAIControl && inputs.control == .effort {
            body["reasoning_effort"] = inputs.effort.rawValue
            body["max_completion_tokens"] = inputs.maxOutputTokens
        } else {
            body["temperature"] = inputs.temperature
            body["top_p"] = inputs.topP
            body["max_tokens"] = inputs.maxOutputTokens
        }
        var request = jsonRequest(url, body: body)
        request?.setValue("Bearer \(inputs.apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func anthropic(_ inputs: Inputs) -> URLRequest? {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { return nil }
        var body: [String: Any] = [
            "model": inputs.model,
            "max_tokens": inputs.maxOutputTokens,
            "system": inputs.systemPrompt,
            "messages": [["role": "user", "content": inputs.userMessage]]
        ]
        if inputs.control == .effort {
            body["output_config"] = ["effort": inputs.effort.rawValue]
            body["thinking"] = ["type": "adaptive"]
        } else {
            body["temperature"] = inputs.temperature
        }
        var request = jsonRequest(url, body: body)
        request?.setValue(inputs.apiKey, forHTTPHeaderField: "x-api-key")
        request?.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }

    private static func google(_ inputs: Inputs) -> URLRequest? {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(inputs.model):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: inputs.apiKey)]
        guard let url = components?.url else { return nil }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": inputs.userMessage]]]],
            "systemInstruction": ["parts": [["text": inputs.systemPrompt]]],
            "generationConfig": [
                "temperature": inputs.temperature,
                "topP": inputs.topP,
                "maxOutputTokens": inputs.maxOutputTokens
            ]
        ]
        return jsonRequest(url, body: body)
    }

    private static func jsonRequest(_ url: URL, body: [String: Any]) -> URLRequest? {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request.httpBody == nil ? nil : request
    }
}

// MARK: - Background session

/// Runs reply requests in a background URLSession and keeps their results
/// until the chat collects them, across suspension and relaunch.
final class BackgroundReplyService: NSObject, URLSessionDataDelegate {

    static let shared = BackgroundReplyService()
    static let sessionIdentifier = "studio.seacloud9.maigexr.replies"
    static let finishedNotification = Notification.Name("BackgroundReplyFinished")

    /// Outcome of one background reply, saved so it survives a relaunch.
    struct Outcome: Codable, Equatable {
        let jobID: String
        let text: String?
        let error: String?
    }

    /// Set by the app delegate when iOS wakes the app for this session.
    var backgroundEventsCompletion: (() -> Void)?

    private let store: UserDefaults
    private let lock = NSLock()
    private var buffers: [Int: Data] = [:]
    private static let outcomesKey = "XRAiAssistant_BackgroundReplyOutcomes"

    init(store: UserDefaults = .standard) {
        self.store = store
        super.init()
    }

    private(set) lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForResource = 15 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    /// Starts `request` in the background. Returns false if it could not start.
    @discardableResult
    func submit(_ request: URLRequest, jobID: String, provider: String) -> Bool {
        guard let body = request.httpBody else { return false }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("reply-\(jobID).json")
        do { try body.write(to: file, options: .atomic) } catch { return false }
        var upload = request
        upload.httpBody = nil
        let task = session.uploadTask(with: upload, fromFile: file)
        task.taskDescription = "\(jobID)|\(provider)"
        task.resume()
        return true
    }

    func cancel(jobID: String) {
        session.getAllTasks { tasks in
            tasks.filter { $0.taskDescription?.hasPrefix(jobID + "|") == true }.forEach { $0.cancel() }
        }
        removeOutcome(jobID: jobID)
    }

    // MARK: Saved outcomes

    func outcome(jobID: String) -> Outcome? {
        outcomes().first { $0.jobID == jobID }
    }

    /// Every finished reply nobody has collected yet (e.g. the app was closed).
    func uncollectedOutcomes() -> [Outcome] { outcomes() }

    func removeOutcome(jobID: String) {
        lock.lock(); defer { lock.unlock() }
        let kept = loadOutcomes().filter { $0.jobID != jobID }
        saveOutcomes(kept)
    }

    func save(_ outcome: Outcome) {
        lock.lock(); defer { lock.unlock() }
        var all = loadOutcomes().filter { $0.jobID != outcome.jobID }
        all.append(outcome)
        saveOutcomes(Array(all.suffix(10)))
    }

    private func outcomes() -> [Outcome] {
        lock.lock(); defer { lock.unlock() }
        return loadOutcomes()
    }

    private func loadOutcomes() -> [Outcome] {
        guard let data = store.data(forKey: Self.outcomesKey) else { return [] }
        return (try? JSONDecoder().decode([Outcome].self, from: data)) ?? []
    }

    private func saveOutcomes(_ outcomes: [Outcome]) {
        store.set(try? JSONEncoder().encode(outcomes), forKey: Self.outcomesKey)
    }

    // MARK: URLSession delegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); buffers[dataTask.taskIdentifier, default: Data()].append(data); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock(); let data = buffers.removeValue(forKey: task.taskIdentifier) ?? Data(); lock.unlock()
        let parts = (task.taskDescription ?? "").split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let (jobID, provider) = (parts[0], parts[1])
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("reply-\(jobID).json"))

        // A cancelled job was superseded by the streamed reply; nothing to keep.
        if let urlError = error as? URLError, urlError.code == .cancelled { return }

        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        let outcome: Outcome
        if let error {
            outcome = Outcome(jobID: jobID, text: nil, error: error.localizedDescription)
        } else if status != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            outcome = Outcome(jobID: jobID, text: nil, error: "HTTP \(status): \(body.prefix(300))")
        } else if let text = BackgroundReplyRequests.replyText(provider: provider, data: data) {
            outcome = Outcome(jobID: jobID, text: text, error: nil)
        } else {
            outcome = Outcome(jobID: jobID, text: nil, error: "The reply could not be read.")
        }
        save(outcome)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.finishedNotification, object: nil, userInfo: ["jobID": jobID])
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundEventsCompletion?()
            self.backgroundEventsCompletion = nil
        }
    }
}

// MARK: - App delegate

/// Lets iOS relaunch the app in the background to finish a reply, and hands the
/// session back to BackgroundReplyService when it does.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        _ = BackgroundReplyService.shared.session // pick up replies still running
        return true
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard identifier == BackgroundReplyService.sessionIdentifier else {
            completionHandler()
            return
        }
        BackgroundReplyService.shared.backgroundEventsCompletion = completionHandler
        _ = BackgroundReplyService.shared.session // reconnects to the running session
    }
}
