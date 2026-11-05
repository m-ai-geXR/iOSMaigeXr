import Foundation

/// A tested Nova64 game engine the AI customises by rewriting its CONFIG.
struct Nova64TemplateInfo {
    let id: String
    let family: String
    let genre: String
    let style: String
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
    private static let families: [(String, String)] = [
        ("dungeon", #"\b(dungeons?|crawlers?|rpg|wizardry|labyrinths?|mazes?|dungeon-crawler)\b"#),
        ("runner", #"\b(runners?|endless run\w*|lanes?|subway|temple run)\b"#),
        ("arena", #"\b(arenas?|dodgers?|dodging|dodge|bullet hell|top-down|survive waves|waves of)\b"#)
    ]
    private static let neon = #"\b(neon|cyber\w*|synth\w*|grid|digital|hacker|tron|data|electric|vapor\w*|laser|sci-?fi|space|holo\w*)\b"#
    private static let classic = #"\b(stone|torch\w*|caves?|cavern|crypts?|tomb|mines?|lava|medieval|castle|forest|corridor|ice|frost|crystal|fantasy)\b"#
    private static let variants: [String: [String: String]] = [
        "dungeon": ["neon": "fp-dungeon-odyssey", "classic": "fp-dungeon-wizardry"],
        "runner": ["neon": "lane-runner-grid", "classic": "lane-runner-corridor"],
        "arena": ["neon": "arena-dodger-neon", "classic": "arena-dodger-cave"]
    ]
    private static let defaultStyle = ["dungeon": "classic", "runner": "neon", "arena": "neon"]
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

    /// Which template a chat request should use, or nil for free-form generation.
    static func choose(message: String, currentTemplateId current: String?) -> String? {
        let m = message.lowercased()
        if matches(optOut, m) { return nil }
        guard let family = families.first(where: { matches($0.1, m) })?.0 else {
            if let current, !matches(newThing, m) { return current }   // follow-up edit
            return nil
        }
        let isNeon = matches(neon, m), isClassic = matches(classic, m)
        if let current, template(current)?.family == family, !isNeon, !isClassic { return current }
        let style = isNeon && !isClassic ? "neon" : isClassic && !isNeon ? "classic" : defaultStyle[family]!
        return variants[family]?[style]
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
