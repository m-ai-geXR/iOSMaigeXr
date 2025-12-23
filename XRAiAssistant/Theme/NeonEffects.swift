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
