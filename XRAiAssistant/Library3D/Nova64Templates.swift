import Foundation

/// A tested Nova64 game engine the AI customises by rewriting its CONFIG.
struct Nova64TemplateInfo {
    let id: String
    let family: String
    let genre: String
    let style: String
    /// Chat words that pick it, from the KEYWORDS const in its CONFIG: game words
    /// choose the kind of game, style words choose this look over the others.
    let gameWords: [String]
    let styleWords: [String]
    let description: String
    let guide: String
    /// Example CONFIG, starting with its `// NOVA64 TEMPLATE: <id>` line.
    let config: String
}

/// Prompt side of the shared Nova64 cart kit (WebMaigeXr/nova64-kit).
///
/// Picks a game template for a chat request and builds the GAME TEMPLATE MODE
/// block. The engines themselves live in the kit inlined in
/// playground-nova64.html, which splices the AI's CONFIG in when the cart runs.
/// The logic mirrors `chooseTemplate` in kit.src.js; `Nova64TemplateData.testVectors`
/// (generated from the JS kit) keeps the two in step.
enum Nova64Templates {
    private static let optOut = #"\b(from scratch|free-?form|without (a |the )?template|no template|custom engine)\b"#
    private static let newThing = #"\b(new|another|different)\b.*\b(scene|game|cart|demo)\b"#
    static let configMark = "// ============================== CONFIG =============================="
    static let engineMark = "// ============================== ENGINE =============================="

    static var all: [Nova64TemplateInfo] { Nova64TemplateData.templates }

    static func template(_ id: String) -> Nova64TemplateInfo? { all.first { $0.id == id } }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// The template id named by a cart's `// NOVA64 TEMPLATE: <id>` line.
    static func templateId(of code: String?) -> String? {
        guard let code,
              let range = code.range(of: #"//\s*NOVA64 TEMPLATE:\s*[a-z0-9-]+"#, options: .regularExpression)
        else { return nil }
        let id = code[range].split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return template(id) != nil ? id : nil
    }

    /// True when `word` starts a word in the lower-cased message ("dodge" matches "dodges").
    static func hasWord(_ message: String, _ word: String) -> Bool {
        var from = message.startIndex
        while let r = message.range(of: word, range: from..<message.endIndex) {
            if r.lowerBound == message.startIndex { return true }
            let before = message[message.index(before: r.lowerBound)]
            if !(before.isASCII && (before.isLetter || before.isNumber)) { return true }
            from = message.index(after: r.lowerBound)
        }
        return false
    }

    private static func matched(_ message: String, _ words: [String]) -> [String] {
        words.filter { hasWord(message, $0) }
    }

    /// Which template a chat request should use and the keywords that picked it.
    /// `id` is nil for free-form; `words` is empty for a follow-up edit.
    static func pick(message: String, currentTemplateId current: String?) -> (id: String?, words: [String]) {
        let m = message.lowercased()
        if matches(optOut, m) { return (nil, []) }
        var best: Nova64TemplateInfo?
        var bestGame: [String] = []
        for t in all {
            let g = matched(m, t.gameWords)
            if g.count > bestGame.count { best = t; bestGame = g }
        }
        guard let best else {
            if let current, !matches(newThing, m) { return (current, []) }   // follow-up edit
            return (nil, [])
        }
        var choice: Nova64TemplateInfo?
        var choiceStyle: [String] = []
        for t in all where t.family == best.family {
            let st = matched(m, t.styleWords)
            if choice == nil || st.count > choiceStyle.count { choice = t; choiceStyle = st }
        }
        if choiceStyle.isEmpty, let current, let cur = template(current), cur.family == best.family { choice = cur }
        return (choice?.id, bestGame + choiceStyle)
    }

    /// Which template a chat request should use, or nil for free-form generation.
    static func choose(message: String, currentTemplateId current: String?) -> String? {
        pick(message: message, currentTemplateId: current).id
    }

    /// A template's chip label in chat: its first game word and first style word.
    static func chipLabel(_ t: Nova64TemplateInfo) -> String {
        "\(t.gameWords.first ?? t.family) \u{00B7} \(t.styleWords.first ?? t.style.lowercased())"
    }

    /// The line that opens a template reply: which template the user's words picked.
    /// Empty for follow-ups and free-form. Matches `templateNote` in kit.src.js.
    static func note(message: String, currentCode: String?) -> String {
        let p = pick(message: message, currentTemplateId: templateId(of: currentCode))
        guard let id = p.id, let t = template(id), !p.words.isEmpty else { return "" }
        let words = p.words.map { "*\($0)*" }.joined(separator: ", ")
        return "\u{1F3AE} Started from the **\(t.genre) \u{00B7} \(t.style)** template, because you said \(words). Tap a template below to preview it, or say *from scratch* to write your own."
    }

    /// The CONFIG section of a cart, from its NOVA64 TEMPLATE line to the ENGINE marker.
    static func config(of code: String) -> String? {
        let start = code.range(of: #"//\s*NOVA64 TEMPLATE:"#, options: .regularExpression)?.lowerBound
            ?? code.range(of: configMark)?.lowerBound
        guard let start else { return nil }
        let end = code.range(of: engineMark, range: start..<code.endIndex)?.lowerBound ?? code.endIndex
        return String(code[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    /// The GAME TEMPLATE MODE block for a request, or nil when it should be free-form.
    static func promptBlock(message: String, currentCode: String?) -> String? {
        let current = templateId(of: currentCode)
        guard let id = choose(message: message, currentTemplateId: current), let t = template(id) else { return nil }
        let config = (current == id ? currentCode.flatMap { self.config(of: $0) } : nil) ?? t.config
        return Nova64TemplateData.promptTemplate
            .replacingOccurrences(of: "{genre}", with: t.genre)
            .replacingOccurrences(of: "{style}", with: t.style)
            .replacingOccurrences(of: "{description}", with: t.description)
            .replacingOccurrences(of: "{guide}", with: t.guide)
            .replacingOccurrences(of: "{id}", with: id)
            .replacingOccurrences(of: "{config}", with: config.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
