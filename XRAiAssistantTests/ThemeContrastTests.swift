import XCTest
import SwiftUI
import UIKit
@testable import XRAiAssistant

/// WCAG AA contrast for the brand palette in both appearances.
///
/// Mirrors ThemeContrastTest on Android: every colour the app draws text in must
/// hold 4.5:1 against the background and the card surface, in light and dark.
final class ThemeContrastTests: XCTestCase {

    private func resolve(_ color: Color, dark: Bool) -> UIColor {
        UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        )
    }

    private func luminance(_ color: UIColor) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private let textColors: [(String, Color)] = [
        ("brandText", .brandText),
        ("brandMuted", .brandMuted),
        ("brandAccentText", .brandAccentText),
        ("brandError", .brandError),
        ("brandWarning", .brandWarning),
        ("brandSuccess", .brandSuccess)
    ]

    private let grounds: [(String, Color)] = [
        ("brandBackground", .brandBackground),
        ("brandSurface", .brandSurface)
    ]

    func testTextColoursMeetWCAGAAInBothAppearances() {
        var failures: [String] = []
        for dark in [false, true] {
            for (textName, text) in textColors {
                for (groundName, ground) in grounds {
                    let ratio = contrast(resolve(text, dark: dark), resolve(ground, dark: dark))
                    if ratio < 4.5 {
                        failures.append(
                            "\(dark ? "dark" : "light"): \(textName) on \(groundName) is " +
                                "\(String(format: "%.2f", ratio)):1"
                        )
                    }
                }
            }
        }
        XCTAssertTrue(failures.isEmpty, "Below 4.5:1 —\n" + failures.joined(separator: "\n"))
    }
}
