import SwiftUI

/// One chip per Nova64 game template, labelled with the words that pick it
/// ("dungeon · stone"). Shown under any reply built on a template, including the
/// Nova64 welcome message. Tapping a chip runs that template's example, so a user
/// can see each one before asking for their own version.
struct Nova64TemplateChips: View {
    /// The template the message was built on, highlighted.
    let activeId: String?
    let onPreview: (_ code: String, _ libraryId: String?) -> Void

    /// Shows the chips when `content` is a Nova64 reply built on a template.
    static func activeTemplate(in content: String, libraryId: String?, isUser: Bool) -> String? {
        guard !isUser, libraryId == "nova64" else { return nil }
        return Nova64Templates.templateId(of: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Game templates: say one of these words, or tap to preview")
                .font(.caption)
                .foregroundColor(.brandMuted)
            ChipFlow(spacing: 8) {
                ForEach(Nova64Templates.all, id: \.id) { t in
                    let active = t.id == activeId
                    Button {
                        onPreview(t.config, "nova64")
                    } label: {
                        Text(Nova64Templates.chipLabel(t))
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(active ? .white : .brandAccentText)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(active ? Color.brandAccent : Color.brandAccent.opacity(0.10)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.vertical, 4) // 44 pt touch target
                    .accessibilityLabel("Preview the \(t.genre), \(t.style) template")
                    .accessibilityHint("Words that pick it: \((t.gameWords + t.styleWords).joined(separator: ", "))")
                }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
    }
}

/// Lays chips out left to right, wrapping onto new lines.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
