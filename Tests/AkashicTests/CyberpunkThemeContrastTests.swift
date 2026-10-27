import XCTest
@testable import Akashic

final class CyberpunkThemeContrastTests: XCTestCase {
    func testReadableMutedTokensMeetWCAGAAOnPanelBackground() {
        let background = CyberpunkTheme.ContrastMetrics.panelBackgroundSRGB
        let minimum = CyberpunkTheme.ContrastMetrics.minimumReadableContrastRatio

        let readableRatio = CyberpunkTheme.ContrastMetrics.wcagContrastRatio(
            foreground: CyberpunkTheme.ContrastMetrics.readableMutedCyanSRGB,
            background: background
        )
        XCTAssertGreaterThanOrEqual(readableRatio, minimum, "readableMutedCyan contrast was \(readableRatio)")

        let completedRatio = CyberpunkTheme.ContrastMetrics.wcagContrastRatio(
            foreground: CyberpunkTheme.ContrastMetrics.completedShadedSRGB,
            background: background
        )
        XCTAssertLessThan(
            completedRatio,
            minimum,
            "Sanity check: completedShaded should remain below AA on pure black (unchanged dim tone)"
        )
    }

    func testCompletedShadedTokenValueUnchanged() {
        let srgb = CyberpunkTheme.ContrastMetrics.completedShadedSRGB
        XCTAssertEqual(srgb.r, 24.0 / 255.0, accuracy: 0.000_1)
        XCTAssertEqual(srgb.g, 72.0 / 255.0, accuracy: 0.000_1)
        XCTAssertEqual(srgb.b, 78.0 / 255.0, accuracy: 0.000_1)
    }
}
