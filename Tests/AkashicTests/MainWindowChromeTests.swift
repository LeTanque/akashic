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

    func testNeonFrameInsetsStayAtDesignValues() {
        XCTAssertEqual(CyberpunkTheme.windowNeonGlowClearance, 14)
        XCTAssertEqual(CyberpunkTheme.windowNeonContentInset, 16)
    }

    func testTopChromeVeilIsDarkerThanWindowSmokeAndCoversTitlebarBand() {
        XCTAssertGreaterThan(CyberpunkTheme.windowTopChromeVeilOpacity, 0.38)
        XCTAssertLessThan(CyberpunkTheme.windowTopChromeVeilOpacity, 0.8)
        XCTAssertGreaterThanOrEqual(CyberpunkTheme.windowTopChromeVeilHeight, 28)
    }

    /// AppKit throws (SIGTRAP via `+[NSApplication _crashOnException:]`) if these
    /// are called on a `.fullSizeContentView` window. Scan the chrome source so
    /// a later titlebar tweak cannot restore the launch crash from PR #7.
    func testChromeSourceDoesNotCallIllegalContentBorderAPIs() throws {
        let chromeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/MainWindowChrome.swift")
        let source = try String(contentsOf: chromeURL, encoding: .utf8)
        XCTAssertFalse(
            source.contains("window.setAutorecalculatesContentBorderThickness"),
            "setAutorecalculatesContentBorderThickness is illegal with .fullSizeContentView"
        )
        XCTAssertFalse(
            source.contains("window.setContentBorderThickness"),
            "setContentBorderThickness is illegal with .fullSizeContentView"
        )
    }
}
