//
//  Colors.swift
//  m{ai}geXR
//
//  Neon Cyberpunk Color Palette
//  Matching Android color definitions exactly
//

import SwiftUI

extension Color {
    // MARK: - Primary Neon Colors

    /// Electric Pink - Primary highlights, logo glow, action buttons
    static let neonPink = Color(red: 1.0, green: 0.0, blue: 0.756)      // #FF00C1

    /// Aqua Cyan - Secondary accents, links, primary UI elements
    static let neonCyan = Color(red: 0.0, green: 1.0, blue: 0.976)      // #00FFF9

    /// Deep Purple - Depth, configuration accents
    static let neonPurple = Color(red: 0.588, green: 0.0, blue: 1.0)    // #9600FF

    /// Neon Blue - Emphasis, info states
    static let neonBlue = Color(red: 0.0, green: 0.722, blue: 1.0)      // #00B8FF

    /// Acid Green - Tertiary accent (code highlights, success states)
    static let neonGreen = Color(red: 0.047, green: 0.913, blue: 0.027) // #0CE907

    // MARK: - Dark Backgrounds

    /// Jet Black - Primary app background
    static let cyberpunkBlack = Color(red: 0.039, green: 0.039, blue: 0.039)      // #0A0A0A

    /// Very Dark Gray - Cards, surfaces, navigation bar
    static let cyberpunkDarkGray = Color(red: 0.102, green: 0.102, blue: 0.102)   // #1A1A1A

    /// Deep Navy - Optional for gradients
    static let cyberpunkNavy = Color(red: 0.051, green: 0.051, blue: 0.122)       // #0D0D1F

    // MARK: - Glow Variants (20% opacity)

    /// Neon Pink glow for shadow effects
    static let neonPinkGlow = Color.neonPink.opacity(0.2)

    /// Neon Cyan glow for shadow effects
    static let neonCyanGlow = Color.neonCyan.opacity(0.2)

    /// Neon Purple glow for shadow effects
    static let neonPurpleGlow = Color.neonPurple.opacity(0.2)

    /// Neon Blue glow for shadow effects
    static let neonBlueGlow = Color.neonBlue.opacity(0.2)

    /// Neon Green glow for shadow effects
    static let neonGreenGlow = Color.neonGreen.opacity(0.2)

    // MARK: - Text Colors

    /// Light gray text for primary content
    static let cyberpunkWhite = Color(red: 0.878, green: 0.878, blue: 0.878)  // #E0E0E0

    /// Medium gray for secondary text
    static let cyberpunkGray = Color(red: 0.502, green: 0.502, blue: 0.502)   // #808080

    /// Dim gray for inactive elements
    static let cyberpunkDimGray = Color(red: 0.290, green: 0.290, blue: 0.290) // #4A4A4A

    // MARK: - Status Colors

    /// Success state color
    static let successNeon = Color.neonGreen

    /// Error state color
    static let errorNeon = Color(red: 1.0, green: 0.0, blue: 0.333)   // #FF0055

    /// Warning state color
    static let warningNeon = Color(red: 1.0, green: 0.667, blue: 0.0) // #FFAA00
}
