import SwiftUI

// MARK: - Premium layout tokens
//
// One set of sizes for controls, corners and separators, so screens stop picking
// their own. Compact controls (30 to 36 pt) read calmer than the 44 to 48 pt
// pills the app used before, while every tappable control keeps a 44 pt hit area
// through `.contentShape` or surrounding padding.

enum Metrics {
    /// Corner radius for cards, sheets and grouped surfaces.
    static let radius: CGFloat = 12
    /// Height of a compact pill such as the model and library selectors.
    static let pillHeight: CGFloat = 30
    /// Height of a compact icon button or the send button.
    static let control: CGFloat = 32
    /// Separator thickness.
    static let hairline: CGFloat = 0.5
}

/// A hairline separator in the brand divider colour.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color.brandDivider)
            .frame(height: Metrics.hairline)
    }
}

/// Compact capsule label for a menu: icon, value, chevron.
struct PillLabel: View {
    let icon: String
    let text: String
    var maxTextWidth: CGFloat = 140

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxTextWidth, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .opacity(0.7)
        }
        .foregroundColor(.brandAccentText)
        .padding(.horizontal, 10)
        .frame(height: Metrics.pillHeight)
        .background(Capsule().fill(Color.brandAccent.opacity(0.10)))
        .contentShape(Capsule())
    }
}

/// Round icon-only button at the compact control size, in a quiet tint.
struct CompactIconButtonStyle: ButtonStyle {
    var tint: Color = .brandMuted

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: Metrics.control, height: Metrics.control)
            .background(Circle().fill(Color.brandSurface.opacity(configuration.isPressed ? 1 : 0.7)))
            .contentShape(Circle())
    }
}

/// The primary action on a message: a compact filled capsule in the accent.
/// Shows a quieter outline when the message has no code block to run.
struct RunSceneLabel: View {
    var hasCode: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "play.fill")
                .font(.system(size: 10, weight: .bold))
            Text("Run scene")
                .font(.caption.weight(.semibold))
        }
        .foregroundColor(hasCode ? .white : .brandAccentText)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(hasCode ? Color.brandAccent : Color.brandAccent.opacity(0.10)))
        .contentShape(Capsule())
    }
}

// MARK: - Screenshot launch argument (debug builds only)

/// `-maigeScreen <name>` opens a screen at launch, so screenshots of every screen
/// can be taken without tapping through the app:
/// `xcrun simctl launch <device> studio.seacloud9.maigexr -maigeScreen examples`.
/// Names: scene, examples, settings, removeads (Settings scrolled to the purchase),
/// history, favorites. Compiled out of release.
enum DebugLaunch {
    static var screen: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "maigeScreen")
        #else
        return nil
        #endif
    }
}
