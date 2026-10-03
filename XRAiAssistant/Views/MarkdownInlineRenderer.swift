import SwiftUI

/// Builds a single `AttributedString` for one line of inline-formatted markdown.
///
/// This exists because composing a line out of several side-by-side `Text` views
/// breaks wrapping: an `HStack` gives each `Text` its own column, so a long run
/// after a short `**bold**` run wraps inside a narrow column on the right rather
/// than flowing across the bubble. One `Text` carrying one `AttributedString`
/// flows and wraps as a single paragraph, which is what we want.
///
/// Kept separate from the view so the parsing and attribute decisions are
/// testable without standing up SwiftUI.
enum MarkdownInlineRenderer {

    /// Thin spaces padding an inline-code run, so its background is not flush
    /// against the surrounding glyphs. An attributed run cannot carry real
    /// padding or rounded corners the way a styled view can.
    static let codePadding = "\u{2009}"

    // MARK: - Rendering

    static func attributedString(from blocks: [InlineBlock], isUser: Bool) -> AttributedString {
        var result = AttributedString()
        for block in blocks {
            result.append(attributedRun(for: block, isUser: isUser))
        }
        return result
    }

    static func attributedString(for line: String, isUser: Bool) -> AttributedString {
        attributedString(from: parse(line), isUser: isUser)
    }

    private static func attributedRun(for block: InlineBlock, isUser: Bool) -> AttributedString {
        let primary: Color = isUser ? .white : .primary

        switch block {
        case .plainText(let text):
            var run = AttributedString(text)
            run.font = .body
            run.foregroundColor = primary
            return run

        case .boldText(let text):
            var run = AttributedString(text)
            run.font = .body.bold()
            run.foregroundColor = primary
            return run

        case .italicText(let text):
            var run = AttributedString(text)
            run.font = .body.italic()
            run.foregroundColor = primary
            return run

        case .code(let code):
            var run = AttributedString(codePadding + code + codePadding)
            run.font = .system(.body, design: .monospaced)
            // On the blue outgoing bubble a systemGray fill reads as mud, and
            // .primary text on it is unreadable; use a translucent white wash.
            run.foregroundColor = isUser ? .white : .primary
            run.backgroundColor = isUser
                ? Color.white.opacity(0.22)
                : Color(.systemGray5)
            return run
        }
    }

    // MARK: - Parsing

    /// Splits one line into inline runs: plain text, `code`, **bold**, *italic*.
    /// An unterminated marker is emitted as literal text rather than swallowing
    /// the rest of the line.
    static func parse(_ text: String) -> [InlineBlock] {
        var blocks: [InlineBlock] = []
        var currentText = ""
        var i = text.startIndex

        func flushPlainText() {
            if !currentText.isEmpty {
                blocks.append(.plainText(currentText))
                currentText = ""
            }
        }

        while i < text.endIndex {
            let char = text[i]

            // Inline code (`code`) - single backticks only
            if char == "`" {
                if String(text[i...]).hasPrefix("```") {
                    // A fence marker; the block parser owns these.
                    currentText.append(char)
                    i = text.index(after: i)
                    continue
                }

                flushPlainText()

                i = text.index(after: i)
                var code = ""
                while i < text.endIndex && text[i] != "`" {
                    code.append(text[i])
                    i = text.index(after: i)
                }

                if i < text.endIndex && text[i] == "`" {
                    blocks.append(.code(code))
                    i = text.index(after: i)
                } else {
                    currentText.append("`")
                    currentText.append(code)
                }
                continue
            }

            // Bold (**text**)
            if char == "*",
               i < text.index(before: text.endIndex),
               text[text.index(after: i)] == "*" {
                let nextIndex = text.index(i, offsetBy: 2, limitedBy: text.endIndex)
                let isTripleAsterisk = nextIndex != nil && nextIndex! < text.endIndex && text[nextIndex!] == "*"

                if isTripleAsterisk {
                    currentText.append(char)
                    i = text.index(after: i)
                    continue
                }

                flushPlainText()

                i = text.index(i, offsetBy: 2)
                var bold = ""
                while i < text.endIndex, text.index(after: i) < text.endIndex {
                    if text[i] == "*" && text[text.index(after: i)] == "*" {
                        break
                    }
                    bold.append(text[i])
                    i = text.index(after: i)
                }

                if i < text.endIndex, text[i] == "*",
                   text.index(after: i) < text.endIndex, text[text.index(after: i)] == "*" {
                    blocks.append(.boldText(bold))
                    i = text.index(i, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                } else {
                    // Unterminated: emit the marker and the consumed tail literally.
                    currentText.append("**")
                    currentText.append(bold)
                    if i < text.endIndex {
                        currentText.append(contentsOf: text[i...])
                        i = text.endIndex
                    }
                }
                continue
            }

            // Italic (*text*)
            if char == "*" {
                flushPlainText()

                i = text.index(after: i)
                var italic = ""
                while i < text.endIndex && text[i] != "*" {
                    italic.append(text[i])
                    i = text.index(after: i)
                }

                if i < text.endIndex && text[i] == "*" {
                    blocks.append(.italicText(italic))
                    i = text.index(after: i)
                } else {
                    currentText.append("*")
                    currentText.append(italic)
                }
                continue
            }

            currentText.append(char)
            i = text.index(after: i)
        }

        flushPlainText()

        return blocks
    }
}
