//
//  Typography.swift
//  m{ai}geXR
//
//  Typography System
//  Font definitions for consistent text styling
//

import SwiftUI

extension Font {
    // MARK: - Display Fonts (Large Headlines)

    /// Large display font (34pt, bold) - Hero text, splash screens
    static let displayLarge = Font.system(size: 34, weight: .bold)

    /// Medium display font (28pt, semibold) - Major section headers
    static let displayMedium = Font.system(size: 28, weight: .semibold)

    /// Small display font (22pt, medium) - Minor section headers
    static let displaySmall = Font.system(size: 22, weight: .medium)

    // MARK: - Headline Fonts

    /// Large headline (20pt, semibold)
    static let headlineLarge = Font.system(size: 20, weight: .semibold)

    /// Medium headline (18pt, semibold)
    static let headlineMedium = Font.system(size: 18, weight: .semibold)

    /// Small headline (16pt, medium)
    static let headlineSmall = Font.system(size: 16, weight: .medium)

    // MARK: - Body Fonts (Main Content)

    /// Large body text (17pt, regular) - Primary content
    static let bodyLarge = Font.system(size: 17, weight: .regular)

    /// Medium body text (15pt, regular) - Standard content
    static let bodyMedium = Font.system(size: 15, weight: .regular)

    /// Small body text (13pt, regular) - Secondary content
    static let bodySmall = Font.system(size: 13, weight: .regular)

    // MARK: - Code Fonts (Monospace)

    /// Large code font (15pt, monospace) - Code blocks
    static let codeLarge = Font.system(size: 15, design: .monospaced)

    /// Medium code font (13pt, monospace) - Inline code
    static let codeMedium = Font.system(size: 13, design: .monospaced)

    /// Small code font (11pt, monospace) - Compact code displays
    static let codeSmall = Font.system(size: 11, design: .monospaced)

    // MARK: - Label Fonts

    /// Large label (14pt, medium) - Form labels
    static let labelLarge = Font.system(size: 14, weight: .medium)

    /// Medium label (12pt, medium) - Secondary labels
    static let labelMedium = Font.system(size: 12, weight: .medium)

    /// Small label (10pt, medium) - Tertiary labels
    static let labelSmall = Font.system(size: 10, weight: .medium)
}

// MARK: - Text Style Modifiers

extension Text {
    /// Apply a neon text glow effect with specified color
    /// - Parameter color: The neon color for the glow (default: neonCyan)
    /// - Returns: Text with subtle neon glow
    func neonText(color: Color = .neonCyan) -> some View {
        self
            .foregroundColor(color)
            .shadow(color: color.opacity(0.15), radius: 2, x: 0, y: 0)
    }

    /// Apply cyberpunk white color (light gray for dark mode)
    /// - Returns: Text with cyberpunk white color
    func cyberpunkWhite() -> some View {
        self.foregroundColor(.cyberpunkWhite)
    }

    /// Apply cyberpunk gray color (medium gray for secondary text)
    /// - Returns: Text with cyberpunk gray color
    func cyberpunkGray() -> some View {
        self.foregroundColor(.cyberpunkGray)
    }
}

// MARK: - Typography Usage Guide
/*
 iOS Typography System - m{ai}geXR

 Based on SF Pro (system default) for compatibility with iOS design language.

 Font Hierarchy:

 1. Display Fonts (34pt, 28pt, 22pt)
    - Use for: Hero text, main titles, splash screens
    - Example: "m{ai}geXR" app title

 2. Headlines (20pt, 18pt, 16pt)
    - Use for: Section headers, card titles, dialogs
    - Example: "Settings", "AI Provider API Keys"

 3. Body Fonts (17pt, 15pt, 13pt)
    - Use for: Main content, descriptions, messages
    - Example: Message bubbles, documentation

 4. Code Fonts (15pt, 13pt, 11pt - Monospace)
    - Use for: Code blocks, inline code, technical data
    - Example: AI-generated code, API responses

 5. Labels (14pt, 12pt, 10pt)
    - Use for: Form labels, buttons, UI controls
    - Example: "Temperature", "Top-P"

 Usage Examples:

 Display:
   Text("m{ai}geXR")
       .font(.displayLarge)
       .neonText(color: .neonCyan)

 Body:
   Text("Natural language to 3D creation")
       .font(.bodyLarge)
       .cyberpunkWhite()

 Code:
   Text("npm install babylon")
       .font(.codeMedium)
       .foregroundColor(.neonGreen)

 Label:
   Text("API Key")
       .font(.labelLarge)
       .cyberpunkGray()
 */
