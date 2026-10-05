import XCTest
import SwiftUI
import UIKit
@testable import XRAiAssistant

/// Guards the message bubble colours against the regression that prompted them.
///
/// The sent bubble used a glass panel tinted with the surface colour, with its
/// text hardcoded white. That was fine while the app was dark only. Once the
/// palette became adaptive, light mode rendered white text on a near-white
/// panel — legible in neither theme by accident, only by luck of the old one.
///
/// These assert the thing that actually matters: whatever the colours are, the
/// text on them has to be readable, in both themes.
final class BubbleContrastTests: XCTestCase {

    private func resolve(_ color: Color, dark: Bool) -> UIColor {
        UIColor(color).resolvedColor(
            with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        )
    }

    /// WCAG relative luminance.
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
        let hi = max(la, lb), lo = min(la, lb)
        return (hi + 0.05) / (lo + 0.05)
    }

    /// WCAG AA for body text.
    private let minimumContrast: CGFloat = 4.5

    func testSentBubbleTextIsReadableInBothThemes() {
        for dark in [false, true] {
            let background = resolve(.brandAccent, dark: dark)
            let text = UIColor.white
            let ratio = contrast(background, text)
            XCTAssertGreaterThanOrEqual(
                ratio, minimumContrast,
                "white on the sent bubble is \(String(format: "%.2f", ratio)):1 in \(dark ? "dark" : "light") mode"
            )
        }
    }

    func testReceivedBubbleTextIsReadableInBothThemes() {
        for dark in [false, true] {
            let background = resolve(.brandSurface, dark: dark)
            let text = resolve(.brandText, dark: dark)
            let ratio = contrast(background, text)
            XCTAssertGreaterThanOrEqual(
                ratio, minimumContrast,
                "body text on the received bubble is \(String(format: "%.2f", ratio)):1 in \(dark ? "dark" : "light") mode"
            )
        }
    }

    /// The specific combination that was broken: white text on the surface tone.
    func testTheOldSentBubbleCombinationWouldFail() {
        let background = resolve(.brandSurface, dark: false)
        let ratio = contrast(background, UIColor.white)
        XCTAssertLessThan(
            ratio, minimumContrast,
            "this is the combination the bug produced; if it now passes, the test no longer guards anything"
        )
    }

    func testSentAndReceivedBubblesAreDistinguishable() {
        for dark in [false, true] {
            let sent = resolve(.brandAccent, dark: dark)
            let received = resolve(.brandSurface, dark: dark)
            XCTAssertGreaterThan(
                contrast(sent, received), 1.5,
                "sent and received bubbles look alike in \(dark ? "dark" : "light") mode"
            )
        }
    }

    func testAccentIsLegibleAgainstTheAppBackground() {
        // The accent is used for links and the active tab, not just fills.
        for dark in [false, true] {
            let background = resolve(.brandBackground, dark: dark)
            let accent = resolve(.brandAccent, dark: dark)
            XCTAssertGreaterThan(
                contrast(background, accent), 3.0,
                "accent on background is weak in \(dark ? "dark" : "light") mode"
            )
        }
    }
}
