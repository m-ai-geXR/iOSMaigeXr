//
//  ChatTheme.swift
//  m{ai}geXR
//
//  Presets for the conversation canvas: its backdrop and how bubbles look.
//
//  Presets rather than free-form styling so every option stays readable and
//  accessible. Each has a light and a dark palette and follows the app's
//  appearance setting, like the rest of the UI.
//

import SwiftUI

enum ChatTheme: String, CaseIterable, Identifiable {
    case clean
    case neonGrid
    case terminal
    case midnight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .neonGrid: return "Neon Grid"
        case .terminal: return "Terminal"
        case .midnight: return "Midnight"
        }
    }

    var monospaced: Bool { self == .terminal }

    /// Every preset has a light and a dark palette and follows the app's
    /// appearance (System, Light or Dark) exactly as Clean does. Text pairs
    /// meet WCAG AA (4.5:1); ChatThemeContrastTests checks them.
    func palette(dark: Bool) -> ChatPalette {
        switch (self, dark) {
        case (.clean, false):
            return ChatPalette(userBubble: 0x2050E0, userText: 0xFFFFFF, aiBubble: 0xEAE9E9, aiText: 0x201E1D,
                               stroke: 0x201E1D, strokeAlpha: 0.18, backdropTop: 0xF3F2F2, backdropBottom: 0xF3F2F2,
                               pattern: 0x201E1D, patternAlpha: 0.18)
        case (.clean, true):
            return ChatPalette(userBubble: 0x3F6BF0, userText: 0xFFFFFF, aiBubble: 0x151821, aiText: 0xF3F2F2,
                               stroke: 0xF3F2F2, strokeAlpha: 0.18, backdropTop: 0x0B0D12, backdropBottom: 0x0B0D12,
                               pattern: 0xF3F2F2, patternAlpha: 0.12)
        case (.neonGrid, false):
            return ChatPalette(userBubble: 0xA21CAF, userText: 0xFFFFFF, aiBubble: 0xFFFFFF, aiText: 0x201E1D,
                               stroke: 0x0891B2, strokeAlpha: 0.45, backdropTop: 0xFAF0FF, backdropBottom: 0xF3F2F2,
                               pattern: 0x0891B2, patternAlpha: 0.12)
        case (.neonGrid, true):
            return ChatPalette(userBubble: 0xA21CAF, userText: 0xFFFFFF, aiBubble: 0x14091F, aiText: 0xF3F2F2,
                               stroke: 0x22D3EE, strokeAlpha: 0.45, backdropTop: 0x1A0B2E, backdropBottom: 0x0B0D12,
                               pattern: 0x22D3EE, patternAlpha: 0.10)
        case (.terminal, false):
            return ChatPalette(userBubble: 0x166534, userText: 0xFFFFFF, aiBubble: 0xFFFFFF, aiText: 0x052E16,
                               stroke: 0x16A34A, strokeAlpha: 0.40, backdropTop: 0xF2FAF4, backdropBottom: 0xF2FAF4,
                               pattern: 0x16A34A, patternAlpha: 0.06)
        case (.terminal, true):
            return ChatPalette(userBubble: 0x0F3D1A, userText: 0x7CFFB0, aiBubble: 0x0A140C, aiText: 0xC8FFD9,
                               stroke: 0x39FF88, strokeAlpha: 0.35, backdropTop: 0x050805, backdropBottom: 0x050805,
                               pattern: 0x39FF88, patternAlpha: 0.04)
        case (.midnight, false):
            return ChatPalette(userBubble: 0x2050E0, userText: 0xFFFFFF, aiBubble: 0xFFFFFF, aiText: 0x201E1D,
                               stroke: 0x1E293B, strokeAlpha: 0.12, backdropTop: 0xE9EDFB, backdropBottom: 0xF3F2F2,
                               pattern: 0x000000, patternAlpha: 0)
        case (.midnight, true):
            return ChatPalette(userBubble: 0x3F6BF0, userText: 0xFFFFFF, aiBubble: 0x141A33, aiText: 0xF3F2F2,
                               stroke: 0xFFFFFF, strokeAlpha: 0.08, backdropTop: 0x0B1026, backdropBottom: 0x05070F,
                               pattern: 0x000000, patternAlpha: 0)
        }
    }

    private func dynamic(_ pick: @escaping (ChatPalette) -> (UInt32, Double)) -> Color {
        Color(UIColor { traits in
            let (hex, alpha) = pick(palette(dark: traits.userInterfaceStyle == .dark))
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        })
    }

    var userBubble: Color { dynamic { ($0.userBubble, 1) } }
    var userText: Color { dynamic { ($0.userText, 1) } }
    var aiBubble: Color { dynamic { ($0.aiBubble, 1) } }
    var aiText: Color { dynamic { ($0.aiText, 1) } }
    var bubbleStroke: Color { dynamic { ($0.stroke, $0.strokeAlpha) } }
    var backdropTop: Color { dynamic { ($0.backdropTop, 1) } }
    var backdropBottom: Color { dynamic { ($0.backdropBottom, 1) } }
    var pattern: Color { dynamic { ($0.pattern, $0.patternAlpha) } }

    /// Small swatch for the picker (follows the current appearance).
    var swatch: [Color] { [backdropTop, userBubble] }
}

/// One appearance of a chat preset, as 0xRRGGBB values so contrast can be tested.
struct ChatPalette {
    let userBubble: UInt32
    let userText: UInt32
    let aiBubble: UInt32
    let aiText: UInt32
    let stroke: UInt32
    let strokeAlpha: Double
    let backdropTop: UInt32
    let backdropBottom: UInt32
    let pattern: UInt32
    let patternAlpha: Double
}

/// The canvas behind the conversation.
struct ChatBackdrop: View {
    let theme: ChatTheme

    var body: some View {
        LinearGradient(colors: [theme.backdropTop, theme.backdropBottom], startPoint: .top, endPoint: .bottom)
            .overlay(pattern)
    }

    @ViewBuilder private var pattern: some View {
        switch theme {
        case .clean: DotGrid(color: theme.pattern, spacing: 22)
        case .neonGrid: LineGrid(color: theme.pattern, spacing: 28)
        case .terminal: Scanlines(color: theme.pattern)
        case .midnight: EmptyView()
        }
    }
}

private struct DotGrid: View {
    let color: Color
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(color))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

private struct LineGrid: View {
    let color: Color
    let spacing: CGFloat

    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0, through: size.width, by: spacing).forEach { x in
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0, through: size.height, by: spacing).forEach { y in
                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(color), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

private struct Scanlines: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0, through: size.height, by: 3).forEach { y in
                path.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
            }
            context.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// A message bubble in the current chat theme.
    func chatBubble(_ theme: ChatTheme, isUser: Bool, cornerRadius: CGFloat = 18) -> some View {
        self
            .foregroundColor(isUser ? theme.userText : theme.aiText)
            .background(isUser ? theme.userBubble : theme.aiBubble)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isUser ? Color.clear : theme.bubbleStroke, lineWidth: 1)
            )
    }
}

extension Color {
    /// 0xRRGGBB, for the fixed colours of the chat presets.
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
