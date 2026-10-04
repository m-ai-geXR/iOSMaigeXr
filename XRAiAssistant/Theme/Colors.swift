//
//  Colors.swift
//  m{ai}geXR
//
//  Brand palette. Values come from brand/brand.json, which mirrors
//  maigexr.seacloud9.studio. Cobalt is the single accent; everything else is a
//  neutral ground.
//
//  Every colour here is adaptive: it resolves through UIColor's trait callback,
//  so one name gives the right value in light and dark without call sites
//  branching on the colour scheme.
//

import SwiftUI
import UIKit

private extension UIColor {
    /// 0xRRGGBB, optionally with alpha.
    convenience init(rgb: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: alpha
        )
    }
}

private func adaptive(light: UInt32, dark: UInt32, alpha: CGFloat = 1.0) -> Color {
    Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(rgb: dark, alpha: alpha)
            : UIColor(rgb: light, alpha: alpha)
    })
}

extension Color {

    // MARK: - Accent

    /// Cobalt. Held a step lighter on dark so it keeps contrast on near-black.
    static let brandAccent = adaptive(light: 0x2050E0, dark: 0x3F6BF0)
    static let brandAccent2 = adaptive(light: 0x4A74EA, dark: 0x5B7EE6)
    static let brandAccentSoft = adaptive(light: 0x8AA6FF, dark: 0x102F96)

    // MARK: - Ground

    static let brandBackground = adaptive(light: 0xF3F2F2, dark: 0x0B0D12)
    static let brandSurface = adaptive(light: 0xEAE9E9, dark: 0x151821)
    static let brandText = adaptive(light: 0x201E1D, dark: 0xF3F2F2)
    static let brandMuted = adaptive(light: 0x605D5D, dark: 0x9B9797)
    static let brandDivider = adaptive(light: 0x201E1D, dark: 0xF3F2F2, alpha: 0.18)

    // MARK: - Status

    static let brandError = adaptive(light: 0xD92D20, dark: 0xF04438)
    static let brandWarning = adaptive(light: 0xB54708, dark: 0xF79009)
    static let brandSuccess = adaptive(light: 0x067647, dark: 0x17B26A)

    // MARK: - Legacy names
    //
    // The neon palette these described is gone. They are kept so the screens
    // that still reference them compile, and because they are adaptive they now
    // render correct brand colours in both themes rather than a fixed dark
    // value. They are misnamed rather than broken; migrate to the brand names
    // above and delete this block.

    static let neonPink = Color.brandAccent
    static let neonCyan = Color.brandAccent
    static let neonPurple = Color.brandAccent2
    static let neonBlue = Color.brandAccent
    static let neonGreen = Color.brandSuccess

    static let cyberpunkBlack = Color.brandBackground
    static let cyberpunkDarkGray = Color.brandSurface
    static let cyberpunkNavy = Color.brandSurface

    static let cyberpunkWhite = Color.brandText
    static let cyberpunkGray = Color.brandMuted
    static let cyberpunkDimGray = Color.brandDivider

    static let successNeon = Color.brandSuccess
    static let errorNeon = Color.brandError
    static let warningNeon = Color.brandWarning

    // Glow tints. The brand is flat, so these are faint surface washes now
    // rather than coloured halos.
    static let neonPinkGlow = Color.brandAccent.opacity(0.12)
    static let neonCyanGlow = Color.brandAccent.opacity(0.12)
    static let neonPurpleGlow = Color.brandAccent2.opacity(0.12)
    static let neonBlueGlow = Color.brandAccent.opacity(0.12)
    static let neonGreenGlow = Color.brandSuccess.opacity(0.12)
}
