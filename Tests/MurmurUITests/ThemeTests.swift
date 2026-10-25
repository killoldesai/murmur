import XCTest
@testable import MurmurUI

final class ThemeTests: XCTestCase {
    typealias P = MurmurTheme.Palette

    func testPaletteMatchesSpec() {
        XCTAssertEqual(P.background, 0x111116)
        XCTAssertEqual(P.surface, 0x1C1C23)
        XCTAssertEqual(P.panel, 0x16161C)
        XCTAssertEqual(P.raised, 0x26262E)
        XCTAssertEqual(P.border, 0x2A2A33)
        XCTAssertEqual(P.accent, 0x5EE0C6)
        XCTAssertEqual(P.onAccent, 0x06231E)
        XCTAssertEqual(P.selectedFill, 0x16302B)
        XCTAssertEqual(P.record, 0xFF5A6E)
        XCTAssertEqual(P.textPrimary, 0xF4F3F8)
        XCTAssertEqual(P.textSecondary, 0xB9B7C8)
        XCTAssertEqual(P.textTertiary, 0x8F8D9C)
        XCTAssertEqual(P.folders, [0x5EE0C6, 0xFFB86B, 0xA9B4FF, 0xFF8FA3, 0x8FD3FF])
    }

    func testTextIsReadableOnItsBackgrounds() {
        // WCAG AA for body text is 4.5:1.
        XCTAssertGreaterThanOrEqual(contrast(P.onAccent, P.accent), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(P.textPrimary, P.background), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(P.textPrimary, P.surface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(P.textSecondary, P.surface), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(P.textTertiary, P.background), 4.5)
        XCTAssertGreaterThanOrEqual(contrast(P.accent, P.selectedFill), 4.5)
    }

    func testStaggerIsWithinSpecRange() {
        XCTAssertGreaterThanOrEqual(MurmurMotion.staggerStep, 0.05)
        XCTAssertLessThanOrEqual(MurmurMotion.staggerStep, 0.08)
        XCTAssertEqual(MurmurMotion.staggerDelay(index: 0), 0)
        XCTAssertEqual(MurmurMotion.staggerDelay(index: -3), 0)
        XCTAssertEqual(MurmurMotion.staggerDelay(index: 5), 5 * MurmurMotion.staggerStep, accuracy: 1e-9)
    }

    func testTapTargetMeetsMinimum() {
        XCTAssertGreaterThanOrEqual(MurmurTheme.Metrics.minTapTarget, 44)
        XCTAssertGreaterThanOrEqual(MurmurTheme.Metrics.buttonHeight, 44)
    }

    // MARK: WCAG contrast helpers

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ v: UInt32) -> Double {
            let c = Double(v) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 0xFF)
            + 0.7152 * channel((hex >> 8) & 0xFF)
            + 0.0722 * channel(hex & 0xFF)
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (hi, lo) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (hi + 0.05) / (lo + 0.05)
    }
}
