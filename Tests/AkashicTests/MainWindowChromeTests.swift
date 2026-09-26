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

    func testHeaderStripIsTightAroundWordmarkRow() {
        XCTAssertEqual(CyberpunkTheme.headerWordmarkHeight, 38)
        XCTAssertEqual(CyberpunkTheme.headerStripVerticalPadding, 4)
        XCTAssertLessThan(
            CyberpunkTheme.headerStripVerticalPadding * 2,
            CyberpunkTheme.headerWordmarkHeight,
            "Vertical pad should stay modest relative to the 38pt wordmark"
        )
        XCTAssertEqual(CyberpunkTheme.headerStripLeadingPadding, 0)
        XCTAssertEqual(CyberpunkTheme.headerStripTrailingPadding, 0)
    }

    func testTopChromeVeilIsDarkerThanWindowSmokeAndCoversTitlebarBand() {
        XCTAssertGreaterThan(CyberpunkTheme.windowTopChromeVeilOpacity, 0.38)
        XCTAssertLessThan(CyberpunkTheme.windowTopChromeVeilOpacity, 0.8)
        XCTAssertGreaterThanOrEqual(CyberpunkTheme.windowTopChromeVeilHeight, 28)
    }

    /// Metrics must sit in the leading column, left of the centered wordmark —
    /// not in the trailing flex band with +/import/close.
    func testHeaderStripSourcePlacesMetricsLeftOfWordmark() throws {
        let themeURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Theme/CyberpunkTheme.swift")
        let source = try String(contentsOf: themeURL, encoding: .utf8)
        guard let stripRange = source.range(of: "struct CyberHeaderStrip") else {
            return XCTFail("CyberHeaderStrip missing")
        }
        let after = String(source[stripRange.lowerBound...])
        let stripEnd = after.range(of: "\nstruct CyberBorderedButtonStyle")?.lowerBound ?? after.endIndex
        let strip = String(after[..<stripEnd])
        guard let metrics = strip.range(of: "HeaderMetricsStrip()"),
              let wordmark = strip.range(of: "AkashicHeaderWordmarkView()")
        else {
            return XCTFail("Header strip is missing metrics or wordmark")
        }
        XCTAssertLessThan(
            metrics.lowerBound,
            wordmark.lowerBound,
            "HeaderMetricsStrip must be laid out before (left of) the wordmark"
        )
        XCTAssertFalse(
            strip.contains("Color.clear"),
            "Leading flex spacer would push metrics off the content's left edge"
        )
        XCTAssertTrue(
            strip.contains("WindowDragRegion()"),
            "Header must keep the window-drag region"
        )
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
