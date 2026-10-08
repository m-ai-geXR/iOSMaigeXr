//
//  ChatTheme.swift
//  m{ai}geXR
//
//  Presets for the conversation canvas: its backdrop and how bubbles look.
//
//  Presets rather than free-form styling so every option stays readable and
//  accessible. Dark presets switch only the message area to dark; the top bar,
//  input and tabs keep following the app appearance.
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

    /// Forces the message area light or dark; nil follows the app.
    var colorScheme: ColorScheme? {
        self == .clean ? nil : .dark
    }

    var monospaced: Bool { self == .terminal }

    var userBubble: Color {
        switch self {
        case .clean, .midnight: return .brandAccent
        case .neonGrid: return Color(hex: 0xA21CAF)
        case .terminal: return Color(hex: 0x0F3D1A)
        }
    }

    var userText: Color {
        self == .terminal ? Color(hex: 0x7CFFB0) : .white
    }

    var aiBubble: Color {
        switch self {
        case .clean: return .brandSurface
        case .neonGrid: return Color.black.opacity(0.55)
        case .terminal: return Color(hex: 0x0A140C)
        case .midnight: return Color(hex: 0x141A33)
        }
    }

    var aiText: Color {
        self == .terminal ? Color(hex: 0xC8FFD9) : .brandText
    }

    /// A thin outline gives bubbles an edge against busy backdrops.
    var bubbleStroke: Color {
        switch self {
        case .clean: return .brandDivider
        case .neonGrid: return Color(hex: 0x22D3EE).opacity(0.45)
        case .terminal: return Color(hex: 0x39FF88).opacity(0.35)
        case .midnight: return Color.white.opacity(0.08)
        }
    }

    /// Small swatch for the picker.
    var swatch: [Color] {
        switch self {
        case .clean: return [.brandBackground, .brandAccent]
        case .neonGrid: return [Color(hex: 0x1A0B2E), Color(hex: 0xA21CAF)]
        case .terminal: return [Color(hex: 0x050805), Color(hex: 0x39FF88)]
        case .midnight: return [Color(hex: 0x0B1026), .brandAccent]
        }
    }
}

/// The canvas behind the conversation.
struct ChatBackdrop: View {
    let theme: ChatTheme

    var body: some View {
        switch theme {
        case .clean:
            Color.brandBackground
                .overlay(DotGrid(color: .brandDivider, spacing: 22))
        case .neonGrid:
            LinearGradient(colors: [Color(hex: 0x1A0B2E), Color(hex: 0x0B0D12)],
                           startPoint: .top, endPoint: .bottom)
                .overlay(LineGrid(color: Color(hex: 0x22D3EE).opacity(0.10), spacing: 28))
        case .terminal:
            Color(hex: 0x050805)
                .overlay(Scanlines(color: Color(hex: 0x39FF88).opacity(0.04)))
        case .midnight:
            LinearGradient(colors: [Color(hex: 0x0B1026), Color(hex: 0x05070F)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
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
                    .stroke(isUser && theme == .clean ? Color.clear : theme.bubbleStroke, lineWidth: 1)
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
