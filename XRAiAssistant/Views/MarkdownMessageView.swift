import SwiftUI

// MARK: - Markdown Message View with Code Block Support
struct MarkdownMessageView: View {
    let content: String
    let isUser: Bool
    @State private var copiedCodeBlocks: Set<Int> = []
    @State private var showCopiedFullMessage = false

    var body: some View {
        // Align message content independently of the outgoing bubble's placement.
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseContent().enumerated()), id: \.offset) { index, block in
                renderBlock(block, index: index)
            }

            // Show "Copied!" indicator when full message is copied
            if showCopiedFullMessage {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                    Text("Message copied!")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.9))
                .cornerRadius(6)
                .transition(.opacity)
            }
        }
        .multilineTextAlignment(.leading)
        .onLongPressGesture(minimumDuration: 0.5) {
            copyFullMessageToClipboard()
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: ContentBlock, index: Int) -> some View {
        switch block {
        case .text(let text):
            Text(text)
                .font(.body)
                .foregroundColor(isUser ? .white : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .codeBlock(let code, let language):
            codeBlockView(code: code, language: language, index: index)

        case .inlineFormattedLine(let blocks):
            // One Text, one AttributedString. Composing this out of several
            // side-by-side Text views in an HStack gave each run its own column,
            // so the long run after a short **bold** run wrapped inside a narrow
            // column instead of flowing across the bubble.
            Text(MarkdownInlineRenderer.attributedString(from: blocks, isUser: isUser))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case .heading(let text, let level):
            Text(text)
                .font(headingFont(for: level))
                .fontWeight(.bold)
                .foregroundColor(isUser ? .white : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

        // Legacy cases - kept for backward compatibility but shouldn't be used directly anymore
        case .inlineCode(let code):
            Text(code)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(.systemGray6))
                .cornerRadius(4)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bold(let text):
            Text(text)
                .fontWeight(.bold)
                .foregroundColor(isUser ? .white : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .italic(let text):
            Text(text)
                .italic()
                .foregroundColor(isUser ? .white : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func codeBlockView(code: String, language: String?, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with language and copy button
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(red: 0.4, green: 0.8, blue: 1.0)) // Bright blue
                }

                Spacer()

                Button(action: {
                    copyToClipboard(code, index: index)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedCodeBlocks.contains(index) ? "checkmark" : "doc.on.doc")
                            .font(.caption)
                        Text(copiedCodeBlocks.contains(index) ? "Copied!" : "Copy")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(copiedCodeBlocks.contains(index) ? 
                               Color.green.opacity(0.8) : 
                               Color(red: 0.3, green: 0.6, blue: 0.9))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.12, green: 0.14, blue: 0.18)) // Dark blue-gray header

            // Code content with enhanced syntax highlighting
            ScrollView(.horizontal, showsIndicators: true) {
                syntaxHighlightedCode(code, language: language)
                    .padding(12)
            }
            .background(Color(red: 0.08, green: 0.10, blue: 0.13)) // Darker code background
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(red: 0.2, green: 0.3, blue: 0.4).opacity(0.3), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func syntaxHighlightedCode(_ code: String, language: String?) -> Text {
        // Use AttributedString to avoid stack overflow from Text concatenation
        // This is CRITICAL for long code blocks to prevent infinite recursion
        var attributedString = AttributedString(code)

        // Enhanced syntax highlighting with better contrast colors
        let keywords = [
            // JavaScript/TypeScript
            "const", "let", "var", "function", "return", "if", "else", "for", "while", "class",
            "import", "export", "from", "new", "this", "true", "false", "null", "undefined",
            // Swift
            "func", "struct", "enum", "protocol", "extension", "private", "public", "static",
            "override", "init", "deinit", "guard", "defer", "await", "async",
            // Python
            "def", "class", "import", "from", "return", "if", "elif", "else", "for", "while",
            "try", "except", "finally", "with", "as", "lambda", "yield",
            // Common
            "async", "await", "break", "case", "catch", "continue", "default", "do",
            "switch", "throw", "throws", "try", "typeof", "void"
        ]

        // Apply base monospaced font and color to entire code block
        attributedString.font = .system(.body, design: .monospaced)
        attributedString.foregroundColor = Color(red: 0.85, green: 0.90, blue: 0.95)

        // Highlight keywords - use regex for better performance
        for keyword in keywords {
            // Match whole words only (with word boundaries)
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsRange = NSRange(code.startIndex..<code.endIndex, in: code)
                let matches = regex.matches(in: code, options: [], range: nsRange)

                for match in matches {
                    if let range = Range(match.range, in: code) {
                        let attributedRange = AttributedString.Index(range.lowerBound, within: attributedString)!..<AttributedString.Index(range.upperBound, within: attributedString)!
                        attributedString[attributedRange].foregroundColor = Color(red: 0.4, green: 0.85, blue: 1.0) // Bright cyan
                        attributedString[attributedRange].font = .system(.body, design: .monospaced).weight(.semibold)
                    }
                }
            }
        }

        return Text(attributedString)
    }

    private func copyToClipboard(_ text: String, index: Int) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif

        // Show copied feedback
        copiedCodeBlocks.insert(index)

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedCodeBlocks.remove(index)
        }
    }

    private func copyFullMessageToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = content
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        #endif

        // Show copied feedback with animation
        withAnimation(.easeInOut(duration: 0.3)) {
            showCopiedFullMessage = true
        }

        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showCopiedFullMessage = false
            }
        }

        // Haptic feedback
        #if os(iOS)
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        #endif
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    // MARK: - Content Cleaning

    private func cleanContent(_ text: String) -> String {
        var cleaned = text

        // Remove common AI response artifacts that appear at the start
        let artifacts = [
            "^A:\\s*",           // "A: "
            "^Assistant:\\s*",   // "Assistant: "
            "^AI:\\s*",          // "AI: "
            "^Response:\\s*"     // "Response: "
        ]

        for artifact in artifacts {
            if let regex = try? NSRegularExpression(pattern: artifact, options: [.anchorsMatchLines]) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    options: [],
                    range: NSRange(location: 0, length: cleaned.utf16.count),
                    withTemplate: ""
                )
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Content Parsing

    private func parseContent() -> [ContentBlock] {
        // Clean up content first - remove common AI response artifacts
        let cleanedContent = cleanContent(content)

        var blocks: [ContentBlock] = []
        let lines = cleanedContent.components(separatedBy: .newlines)
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Code block detection (```) - MUST be checked first and be strict
            // Only match if ``` is at the start of the line (after whitespace)
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("```") && !trimmedLine.hasPrefix("`````") {
                let language = trimmedLine
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: .whitespaces)

                var codeLines: [String] = []
                i += 1

                // Collect all lines until we find the closing ```
                while i < lines.count {
                    let codeLine = lines[i]
                    let trimmedCodeLine = codeLine.trimmingCharacters(in: .whitespaces)
                    if trimmedCodeLine.hasPrefix("```") {
                        break
                    }
                    codeLines.append(codeLine)
                    i += 1
                }

                let code = codeLines.joined(separator: "\n")
                print("📦 Code block extracted: \(codeLines.count) lines, \(code.count) chars")
                print("📝 Code block preview: \(code.prefix(100))...")
                print("📝 Code block END: ...\(code.suffix(100))")
                blocks.append(.codeBlock(code: code, language: language.isEmpty ? nil : language))
                i += 1
                continue
            }

            // Heading detection (must be at line start)
            if line.hasPrefix("#") {
                let level = line.prefix(while: { $0 == "#" }).count
                let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(text: text, level: level))
                i += 1
                continue
            }

            // Lines with inline code, bold, or italic formatting
            // This handles mixed content like "Use `const` or `let` for variables"
            if line.contains("`") || line.contains("*") {
                let inlineBlocks = MarkdownInlineRenderer.parse(line)
                // Only create inline formatted line if we have content
                if !inlineBlocks.isEmpty {
                    blocks.append(.inlineFormattedLine(inlineBlocks))
                }
                i += 1
                continue
            }

            // Regular text
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                blocks.append(.text(line))
            }

            i += 1
        }
        
        return blocks
    }

}

// MARK: - Content Block Types
enum ContentBlock {
    case text(String)
    case codeBlock(code: String, language: String?)
    case inlineFormattedLine([InlineBlock])  // New: for lines with mixed inline formatting
    case heading(text: String, level: Int)
    // Legacy cases - kept for backward compatibility
    case inlineCode(String)
    case bold(String)
    case italic(String)
}

// MARK: - Inline Block Types (for mixed formatting on a single line)
enum InlineBlock {
    case plainText(String)
    case code(String)
    case boldText(String)
    case italicText(String)
}

// MARK: - Preview
#Preview {
    VStack(spacing: 20) {
        MarkdownMessageView(
            content: """
            Here's a **bold** example with *italic* text.

            # Heading 1
            ## Heading 2

            Inline code: `const x = 42;`

            ```javascript
            function hello() {
                console.log("Hello, World!");
                return true;
            }
            ```

            ```python
            def fibonacci(n):
                if n <= 1:
                    return n
                return fibonacci(n-1) + fibonacci(n-2)
            ```
            
            To use this code, call `runCode()` or use the **Run** button. You can also use `insertCodeAtCursor()` for *inline* insertion.
            """,
            isUser: false
        )
        .padding()
        .background(Color(.systemGray5))
        .cornerRadius(16)
        .padding()
    }
}
