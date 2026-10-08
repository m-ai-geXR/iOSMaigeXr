import Foundation

/// The chat models the user's Together key can use right now, from
/// `GET /v1/models`. Together retires models (DeepSeek R1 went without notice),
/// so a live list keeps the picker honest: curated models the key cannot use
/// drop out, and everything else the key can use is offered too. With no key,
/// no network or no cached list, the built-in list is used unchanged.
final class TogetherModelCatalog {
    static let shared = TogetherModelCatalog()

    struct LiveModel: Codable, Equatable {
        let id: String
        let displayName: String
        let organization: String?
        let contextLength: Int?
        let inputPricePerMillion: Double
    }

    /// The group the extra models appear under in the picker.
    static let moreGroup = "Together.ai · More"

    private static let cacheKey = "XRAiAssistant_TogetherLiveModels"
    private static let fetchedAtKey = "XRAiAssistant_TogetherLiveModelsFetchedAt"
    private static let maxAge: TimeInterval = 24 * 60 * 60

    private let store: UserDefaults

    init(store: UserDefaults = .standard) {
        self.store = store
    }

    /// The last list fetched for the current key, if any.
    var cached: [LiveModel]? {
        guard let data = store.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode([LiveModel].self, from: data)
    }

    var isStale: Bool {
        let fetchedAt = store.object(forKey: Self.fetchedAtKey) as? Date ?? .distantPast
        return Date().timeIntervalSince(fetchedAt) > Self.maxAge
    }

    func clear() {
        store.removeObject(forKey: Self.cacheKey)
        store.removeObject(forKey: Self.fetchedAtKey)
    }

    /// Fetches the list for `apiKey` and caches it. Keeps the old list on failure.
    @discardableResult
    func refresh(apiKey: String) async -> Bool {
        guard !apiKey.isEmpty, apiKey != "changeMe",
              let url = URL(string: "https://api.together.xyz/v1/models") else { return false }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let models = Self.parse(data)
            guard !models.isEmpty else { return false }
            store.set(try JSONEncoder().encode(models), forKey: Self.cacheKey)
            store.set(Date(), forKey: Self.fetchedAtKey)
            print("📚 Together models for this key: \(models.count)")
            return true
        } catch {
            print("⚠️ Could not fetch Together models: \(error.localizedDescription)")
            return false
        }
    }

    /// Chat models billed per token. Together's list has no serverless flag;
    /// dedicated-only models are billed by the hour with no per-token price,
    /// so per-token pricing is what marks a model as usable on demand.
    static func parse(_ data: Data) -> [LiveModel] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let items = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["data"] as? [[String: Any]]) ?? []
        return items.compactMap { item in
            guard let id = item["id"] as? String, item["type"] as? String == "chat" else { return nil }
            let pricing = item["pricing"] as? [String: Any] ?? [:]
            let input = (pricing["input"] as? NSNumber)?.doubleValue ?? 0
            let output = (pricing["output"] as? NSNumber)?.doubleValue ?? 0
            guard input > 0 || output > 0 else { return nil }
            return LiveModel(
                id: id,
                displayName: (item["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? id,
                organization: item["organization"] as? String,
                contextLength: (item["context_length"] as? NSNumber)?.intValue,
                inputPricePerMillion: input
            )
        }
    }

    /// The models to offer: curated ones the key can use, in their order, then
    /// the rest of the key's chat models by name. Without a live list, curated.
    static func merge(curated: [AIModel], live: [LiveModel]?) -> [AIModel] {
        guard let live, !live.isEmpty else { return curated }
        let liveIDs = Set(live.map(\.id))
        let kept = curated.filter { liveIDs.contains($0.id) }
        let curatedIDs = Set(curated.map(\.id))
        let extras = live
            .filter { !curatedIDs.contains($0.id) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map { model -> AIModel in
                var details: [String] = []
                if let org = model.organization, !org.isEmpty { details.append(org) }
                if let context = model.contextLength, context > 0 { details.append("\(context / 1000)K context") }
                return AIModel(
                    id: model.id,
                    displayName: model.displayName,
                    description: details.isEmpty ? "Together model" : details.joined(separator: " · "),
                    pricing: String(format: "$%.2f/1M input tokens", model.inputPricePerMillion),
                    provider: moreGroup
                )
            }
        // Never leave the key with nothing: if no curated model survived, keep them.
        return (kept.isEmpty ? curated : kept) + extras
    }
}
