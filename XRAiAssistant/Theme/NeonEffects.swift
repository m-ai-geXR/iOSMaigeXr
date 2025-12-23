//
//  NeonEffects.swift
//  m{ai}geXR
//
//  Neon Glow Effect Modifiers
//  SwiftUI modifiers for cyberpunk visual effects
//

import SwiftUI

extension View {
    // MARK: - Basic Neon Glow (8pt)

    /// Apply a basic neon glow effect (8pt blur radius, standard glow)
    /// - Parameters:
    ///   - color: The neon color for the glow
    ///   - radius: Blur radius (default 8pt)
    /// - Returns: View with neon glow shadow
    func neonGlow(color: Color, radius: CGFloat = 8) -> some View {
        self.shadow(color: color.opacity(0.35), radius: radius, x: 0, y: 0)
    }

    // MARK: - Neon Border with Glow

    /// Apply a neon-colored border with glow effect
    /// - Parameters:
    ///   - color: The neon color for border and glow
    ///   - width: Border width (default 1.5pt)
    ///   - glowRadius: Glow blur radius (default 8pt)
    ///   - cornerRadius: Corner radius for the border (default 8pt)
    /// - Returns: View with neon border and glow
    func neonBorder(color: Color, width: CGFloat = 1.5, glowRadius: CGFloat = 8, cornerRadius: CGFloat = 8) -> some View {
        self
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(color, lineWidth: width)
            )
            .shadow(color: color.opacity(0.35), radius: glowRadius, x: 0, y: 0)
    }

    // MARK: - Neon Button Glow (12pt - Strongest)

    /// Apply the strongest neon glow for interactive buttons
    /// - Parameter color: The neon color for the glow
    /// - Returns: View with maximum impact glow (12pt blur)
    func neonButtonGlow(color: Color) -> some View {
        self.shadow(color: color.opacity(0.35), radius: 12, x: 0, y: 0)
    }

    // MARK: - Neon Input Glow (10pt - Strong)

    /// Apply a strong glow for text input fields
    /// - Parameter color: The neon color for the glow
    /// - Returns: View with strong glow (10pt blur)
    func neonInputGlow(color: Color) -> some View {
        self.shadow(color: color.opacity(0.35), radius: 10, x: 0, y: 0)
    }

    // MARK: - Neon Card Glow (8pt - Balanced)

    /// Apply a balanced glow for cards and containers
    /// - Parameter color: The neon color for the glow
    /// - Returns: View with balanced glow (8pt blur)
    func neonCardGlow(color: Color) -> some View {
        self.shadow(color: color.opacity(0.35), radius: 8, x: 0, y: 0)
    }

    // MARK: - Neon Dual Glow (Layered)

    /// Apply a layered dual-color glow for enhanced depth
    /// - Parameters:
    ///   - primary: Primary glow color (outer, 12pt)
    ///   - secondary: Secondary glow color (inner, 6pt)
    /// - Returns: View with layered glow effect
    func neonDualGlow(primary: Color, secondary: Color) -> some View {
        self
            .shadow(color: primary.opacity(0.3), radius: 12, x: 0, y: 0)
            .shadow(color: secondary.opacity(0.4), radius: 6, x: 0, y: 0)
    }

    // MARK: - Neon Text Glow

    /// Apply a subtle text glow effect
    /// - Parameter color: The neon color for the glow
    /// - Returns: View with subtle text glow
    func neonTextGlow(color: Color) -> some View {
        self.shadow(color: color.opacity(0.15), radius: 2, x: 0, y: 0)
    }

    // MARK: - Glass Effects (Glassmorphism)

    /// Apply a glass effect with blur and semi-transparency
    /// - Parameters:
    ///   - tintColor: Background tint color (default cyberpunk dark gray)
    ///   - opacity: Background opacity (default 0.7 for glass effect)
    ///   - cornerRadius: Corner radius (default 12pt)
    ///   - borderColor: Optional border color with glow
    /// - Returns: View with glassmorphism effect
    func glassEffect(
        tintColor: Color = .cyberpunkDarkGray,
        opacity: Double = 0.7,
        cornerRadius: CGFloat = 12,
        borderColor: Color? = nil
    ) -> some View {
        self
            .background(
                ZStack {
                    // Glass background with blur
                    tintColor.opacity(opacity)

                    // Subtle gradient overlay for depth
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.1),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .background(.ultraThinMaterial)
                .cornerRadius(cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor ?? Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .shadow(color: borderColor?.opacity(0.2) ?? Color.clear, radius: borderColor != nil ? 8 : 0, x: 0, y: 0)
    }

    /// Apply a premium glass card effect with neon accent
    /// - Parameters:
    ///   - accentColor: Neon accent color for border glow
    ///   - cornerRadius: Corner radius (default 16pt)
    /// - Returns: View with premium glass card styling
    func glassCard(accentColor: Color = .neonCyan, cornerRadius: CGFloat = 16) -> some View {
        self
            .padding()
            .glassEffect(
                tintColor: .cyberpunkDarkGray,
                opacity: 0.6,
                cornerRadius: cornerRadius,
                borderColor: accentColor
            )
    }

    /// Apply a frosted glass input field effect
    /// - Parameter accentColor: Neon accent color for active state
    /// - Returns: View with frosted input styling
    func glassInput(accentColor: Color = .neonCyan) -> some View {
        self
            .padding(12)
            .glassEffect(
                tintColor: .cyberpunkDarkGray,
                opacity: 0.5,
                cornerRadius: 8,
                borderColor: accentColor
            )
    }
}

// MARK: - Glow Hierarchy Reference
/*
 Glow Hierarchy (Following Android Brand Guide):

 - Interactive elements (buttons): 12pt blur - Maximum impact
 - Input fields: 10pt blur - Strong presence
 - Basic elements: 8pt blur - Noticeable glow
 - Cards/containers: 8pt blur - Balanced subtlety
 - Text: 2pt blur - Subtle enhancement

 Usage Examples:

 Button:
   .neonButtonGlow(color: .neonPink)

 TextField:
   .neonInputGlow(color: .neonCyan)

 Card:
   .neonCardGlow(color: .neonBlue)

 Border with Glow:
   .neonBorder(color: .neonPurple, width: 1.5, glowRadius: 8)

 Custom:
   .neonGlow(color: .neonGreen, radius: 10)
 */
