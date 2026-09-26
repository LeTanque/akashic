import XCTest
@testable import Akashic

final class MainWindowChromeTests: XCTestCase {
    func testReservedTopUsesContentLayoutGapNotNeonInsets() {
        let content = CGRect(x: 0, y: 0, width: 800, height: 600)
        let fullLayout = content
        XCTAssertEqual(
            MainWindowTitlebarMetrics.reservedTop(
                contentBounds: content,
                contentLayoutInContentView: fullLayout
            ),
            0
        )

        // Typical hidden titlebar still reports ~28pt via contentLayoutRect.
        let insetLayout = CGRect(x: 0, y: 0, width: 800, height: 572)
        XCTAssertEqual(
            MainWindowTitlebarMetrics.reservedTop(
                contentBounds: content,
                contentLayoutInContentView: insetLayout
            ),
            28
        )
    }

    func testNeonFrameInsetsWereNotShrunk() {
        XCTAssertEqual(CyberpunkTheme.windowNeonGlowClearance, 14)
        XCTAssertEqual(CyberpunkTheme.windowNeonContentInset, 16)
    }
}
