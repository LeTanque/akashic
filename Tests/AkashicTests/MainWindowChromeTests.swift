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

    /// Metrics flush left, wordmark geometrically centered in the window,
    /// buttons flush right — not an equal-flex HStack that shifts the logo
    /// when the two side clusters have different widths.
    func testHeaderStripSourceCentersWordmarkIndependentlyOfSideColumns() throws {
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
        XCTAssertTrue(
            strip.contains("ZStack"),
            "Wordmark must be overlaid at the window center, not flex-centered between unequal columns"
        )
        XCTAssertTrue(
            strip.contains("HeaderMetricsStrip()"),
            "Header strip is missing metrics"
        )
        XCTAssertTrue(
            strip.contains("AkashicHeaderWordmarkView()"),
            "Header strip is missing the wordmark"
        )
        XCTAssertTrue(
            strip.contains("Spacer(minLength:"),
            "HStack must push metrics left and buttons right around the centered wordmark"
        )
        XCTAssertFalse(
            strip.contains("Color.clear"),
            "Leading flex spacer would push metrics off the content's left edge"
        )
        XCTAssertFalse(
            strip.contains("layoutPriority"),
            "layoutPriority on a flex column starves the other side (PR #10 ViewThatFits collapse)"
        )
        XCTAssertTrue(
            strip.contains("WindowDragRegion()"),
            "Header must keep the window-drag region"
        )
    }

    /// The main-window HUD must always render APP/SYS + CPU/CA. ViewThatFits
    /// falling back to short (APP+CA) or minimal (APP) is the PR #10 bug.
    func testHeaderMetricsStripAlwaysShowsFullTwoRows() throws {
        let stripURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/HeaderMetricsStrip.swift")
        let source = try String(contentsOf: stripURL, encoding: .utf8)
        XCTAssertTrue(
            source.contains("stacked(lines.full)"),
            "Header metrics must render the full APP/SYS + CPU/CA rows"
        )
        XCTAssertFalse(
            source.contains("ViewThatFits("),
            "ViewThatFits must not drop SYS/CPU when the leading column is tight"
        )
        XCTAssertFalse(source.contains("lines.short"), "short row pair omits SYS/CPU")
        XCTAssertFalse(source.contains("lines.minimal"), "minimal row omits SYS/CPU/CA")
        XCTAssertFalse(source.contains("lines.compact"), "compact row omits SYS")
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
