import Foundation

/// Plain-text names and previews for list rows, shared by History and Favorites.
/// The same rules as Android's FavoriteTitle and MessagePreview, so both apps name
/// a scene the same way.
enum SceneText {
    static let maxTitleLength = 50
    static let maxPreviewLength = 160

    /// The name the AI gave the scene: its first markdown heading, else a bold
    /// lead sentence. Nil when the reply named nothing.
    static func title(fromReply reply: String?) -> String? {
        let prose = proseBeforeCode(reply)
        if let heading = firstMatch(#"(?m)^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$"#, in: prose) {
            let cleaned = clean(heading)
            if !cleaned.isEmpty { return clamp(cleaned) }
        }
        let firstLine = prose.split(separator: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if let line = firstLine, let bold = firstMatch(#"^\s*\*\*(.+?)\*\*"#, in: String(line)) {
            let cleaned = clean(bold)
            if !cleaned.isEmpty { return clamp(cleaned) }
        }
        return nil
    }

    /// First line of code that is not blank or a comment.
    static func title(fromCode code: String) -> String {
        let line = code.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("/*") && !$0.hasPrefix("*") }
        return line.map(clamp) ?? "Untitled Scene"
    }

    /// The title the app used to store: the first non-comment code line, cut at
    /// 50 characters. Used to recognise favorites saved before scene naming.
    static func legacyTitle(fromCode code: String) -> String {
        let line = code.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("/*") }
        return line.map { String($0.prefix(50)) } ?? "Untitled Scene"
    }

    /// A preview that does not repeat the row's title as its opening words.
    static func preview(of reply: String?, droppingTitle title: String?) -> String? {
        guard var text = preview(of: reply) else { return nil }
        if let title, !title.isEmpty, text.lowercased().hasPrefix(title.lowercased()) {
            text = String(text.dropFirst(title.count).drop { " .:!—-–".contains($0) || $0.isWhitespace })
        }
        return text.isEmpty ? nil : text
    }

    /// One line of prose from a reply, without code or markdown.
    static func preview(of reply: String?) -> String? {
        var text = proseBeforeCode(reply)
        text = replace(#"\[([^\]]*)\]\([^)]*\)"#, in: text, with: "$1")
        text = replace(#"(?m)^\s{0,3}#{1,6}\s+"#, in: text, with: "")
        text = replace(#"[*_`~>]"#, in: text, with: "")
        text = replace(#"\s+"#, in: text, with: " ").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return text.count <= maxPreviewLength ? text : String(text.prefix(maxPreviewLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Helpers

    private static func proseBeforeCode(_ reply: String?) -> String {
        guard let reply else { return "" }
        let prose = reply.components(separatedBy: "```").first ?? reply
        return prose.replacingOccurrences(of: "[INSERT_CODE]", with: "")
    }

    private static func clean(_ text: String) -> String {
        var t = replace(#"[*_`~]"#, in: text, with: "")
        t = replace(#"\[([^\]]*)\]\([^)]*\)"#, in: t, with: "$1")
        t = t.trimmingCharacters(in: .whitespaces)
        while let last = t.last, ".:!;,".contains(last) { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func clamp(_ text: String) -> String {
        guard text.count > maxTitleLength else { return text }
        let cut = String(text.prefix(maxTitleLength - 1))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= maxTitleLength / 2 {
            return String(cut[..<space]).trimmingCharacters(in: .whitespaces) + "…"
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
