import XCTest
@testable import XRAiAssistant

/// Every chat style, in light and dark, must keep message text readable:
/// WCAG AA asks for 4.5:1 between text and its background.
final class ChatThemeContrastTests: XCTestCase {

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF) + 0.7152 * channel((hex >> 8) & 0xFF) + 0.0722 * channel(hex & 0xFF)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    func testEveryStyleIsReadableInLightAndDark() {
        for theme in ChatTheme.allCases {
            for dark in [false, true] {
                let p = theme.palette(dark: dark)
                let name = "\(theme.displayName) \(dark ? "dark" : "light")"
                XCTAssertGreaterThanOrEqual(contrast(p.userText, p.userBubble), 4.5, "\(name) user text")
                XCTAssertGreaterThanOrEqual(contrast(p.aiText, p.aiBubble), 4.5, "\(name) reply text")
                // What MarkdownMessageView actually draws: white on sent messages,
                // the system label colour (near black or white) on replies.
                XCTAssertGreaterThanOrEqual(contrast(0xFFFFFF, p.userBubble), 4.5, "\(name) sent text as drawn")
                XCTAssertGreaterThanOrEqual(contrast(dark ? 0xFFFFFF : 0x000000, p.aiBubble), 4.5, "\(name) reply text as drawn")
            }
        }
    }

    func testDarkStylesAreActuallyDarkAndLightOnesLight() {
        for theme in ChatTheme.allCases {
            XCTAssertLessThan(luminance(theme.palette(dark: true).backdropTop), 0.05, "\(theme) dark backdrop")
            XCTAssertGreaterThan(luminance(theme.palette(dark: false).backdropTop), 0.8, "\(theme) light backdrop")
        }
    }
}
