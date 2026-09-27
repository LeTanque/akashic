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
        XCTAssertEqual(CyberpunkTheme.headerWordmarkHeight, 48)
        XCTAssertEqual(CyberpunkTheme.headerStripVerticalPadding, 4)
        XCTAssertLessThan(
            CyberpunkTheme.headerStripVerticalPadding * 2,
            CyberpunkTheme.headerWordmarkHeight,
            "Vertical pad should stay modest relative to the wordmark height"
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

    /// The main-window HUD must always render both machine + usage rows. ViewThatFits
    /// falling back to short rows is the PR #10 bug.
    func testHeaderMetricsStripAlwaysShowsFullRows() throws {
        let stripURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/HeaderMetricsStrip.swift")
        let source = try String(contentsOf: stripURL, encoding: .utf8)
        XCTAssertTrue(
            source.contains("stacked(lines.full)"),
            "Header metrics must render the full machine + Cursor usage rows"
        )
        XCTAssertFalse(
            source.contains("ViewThatFits("),
            "ViewThatFits must not drop SYS/CPU when the leading column is tight"
        )
        XCTAssertFalse(source.contains("lines.short"), "short row pair omits SYS/CPU")
        XCTAssertFalse(source.contains("lines.minimal"), "minimal row omits SYS/CPU")
        XCTAssertFalse(source.contains("lines.compact"), "compact row omits SYS")
        XCTAssertFalse(source.contains("AgentMetricsStore"), "CA feeder must not drive the header HUD")
    }

    /// AppKit throws (SIGTRAP via `+[NSApplication _crashOnException:]`) if these
    /// are called on a `.fullSizeContentView` window. Scan the chrome source so
    /// a later titlebar tweak cannot restore the launch crash from PR #7.
    /// When the editor is hidden but the todo list stays visible, the list column must
    /// expand like the detail column does when the sidebar is hidden (not stay capped at 420pt).
    func testMainWindowExpandsTodoListWhenEditorHidden() throws {
        let viewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/MainWindowView.swift")
        let source = try String(contentsOf: viewURL, encoding: .utf8)
        XCTAssertTrue(
            source.contains("sidebarExpandsToFill"),
            "Main window must detect editor-hidden + sidebar-visible layout"
        )
        guard let expandsRange = source.range(of: "sidebarExpandsToFill") else {
            return XCTFail("sidebarExpandsToFill missing")
        }
        let afterExpands = String(source[expandsRange.lowerBound...])
        guard let todoRange = afterExpands.range(of: "private var todoListColumn") else {
            return XCTFail("todoListColumn missing")
        }
        let todoBlock = String(afterExpands[todoRange.lowerBound...].prefix(800))
        XCTAssertTrue(
            todoBlock.contains("if sidebarExpandsToFill"),
            "Todo list frame must branch when the editor is hidden"
        )
        XCTAssertTrue(
            todoBlock.contains("maxWidth: .infinity, maxHeight: .infinity"),
            "Expanded todo list must fill the content area"
        )
    }

    func testMainWindowHeaderTogglesSidebarAndEditorFromVisibilityStores() throws {
        let viewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/MainWindowView.swift")
        let source = try String(contentsOf: viewURL, encoding: .utf8)
        guard let actionsRange = source.range(of: "private var headerActions") else {
            return XCTFail("headerActions missing")
        }
        let actions = String(source[actionsRange.lowerBound...].prefix(2200))
        XCTAssertTrue(actions.contains("sidebarVisibility.toggle()"))
        XCTAssertTrue(actions.contains("mainSectionVisibility.toggle()"))
        XCTAssertTrue(actions.contains("sidebar.leading"))
        XCTAssertTrue(actions.contains("sidebar.trailing"))
        XCTAssertTrue(actions.contains("sidebarVisibility.headerTooltip"))
        XCTAssertTrue(actions.contains("mainSectionVisibility.headerTooltip"))
    }

    func testMainWindowHeaderHasNoImportControls() throws {
        let viewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/MainWindowView.swift")
        let source = try String(contentsOf: viewURL, encoding: .utf8)
        guard let actionsRange = source.range(of: "private var headerActions") else {
            return XCTFail("headerActions missing")
        }
        let actions = String(source[actionsRange.lowerBound...].prefix(1200))
        XCTAssertFalse(actions.contains("importSeedFromBundle"))
        XCTAssertFalse(actions.contains("importFromFile"))
        XCTAssertFalse(actions.contains("square.and.arrow.down"))
        XCTAssertFalse(actions.contains("doc.badge.arrow.up"))
    }

    func testMainWindowHeaderHasNoCloseButton() throws {
        let viewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/MainWindowView.swift")
        let source = try String(contentsOf: viewURL, encoding: .utf8)
        guard let actionsRange = source.range(of: "private var headerActions") else {
            return XCTFail("headerActions missing")
        }
        let actions = String(source[actionsRange.lowerBound...].prefix(900))
        XCTAssertFalse(actions.contains("dismissWindow"))
        XCTAssertFalse(actions.contains("Close main window"))
    }

    func testMenuBarMenuOffersDestructiveImportsWithConfirmation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let menuSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Views/MenuBarMenuView.swift"),
            encoding: .utf8
        )
        let confirmSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Services/AkashicImportConfirmations.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(menuSource.contains("Import Demo Seed"))
        XCTAssertTrue(menuSource.contains("Import JSON"))
        XCTAssertTrue(menuSource.contains("AkashicImportConfirmations.confirmReplaceWithBundledSeed()"))
        XCTAssertTrue(menuSource.contains("AkashicImportConfirmations.confirmReplaceWithJSONFile()"))
        XCTAssertTrue(confirmSource.contains("Replace all todos?"))
        XCTAssertTrue(confirmSource.contains("alertStyle = .warning"))
    }

    func testHeaderAndMenuBarMenuRemoveFullscreenControls() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let mainSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Views/MainWindowView.swift"),
            encoding: .utf8
        )
        let menuSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Views/MenuBarMenuView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(mainSource.contains("MainWindowFullscreenTracker"))
        XCTAssertFalse(mainSource.contains("toggleFullScreen"))
        XCTAssertFalse(mainSource.contains("arrow.up.left.and.arrow.down.right"))
        XCTAssertFalse(menuSource.contains("MainWindowFullscreenTracker"))
        XCTAssertFalse(menuSource.contains("toggleFullScreen"))
        XCTAssertFalse(menuSource.contains("arrow.up.left.and.arrow.down.right"))
        let trackerURL = root.appendingPathComponent("Sources/Akashic/Services/MainWindowFullscreenTracker.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: trackerURL.path))
    }

    /// Status item must use the system menu, not the Akashic-themed popover panel.
    func testMenuBarExtraUsesStandardSystemMenu() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/AkashicApp.swift"),
            encoding: .utf8
        )
        let menuSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Views/MenuBarMenuView.swift"),
            encoding: .utf8
        )
        let chromeSource = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Views/MainWindowChrome.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(appSource.contains(".menuBarExtraStyle(.menu)"))
        XCTAssertFalse(appSource.contains(".menuBarExtraStyle(.window)"))
        XCTAssertTrue(appSource.contains("MenuBarMenuView()"))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Sources/Akashic/Views/MenuBarPopoverView.swift").path
            )
        )
        XCTAssertFalse(menuSource.contains("CyberpunkTheme"))
        XCTAssertFalse(menuSource.contains("SmokedGlassFill"))
        XCTAssertFalse(menuSource.contains("PopoverWindowTranslucencyConfigurator"))
        XCTAssertFalse(menuSource.contains("CyberBorderedButtonStyle"))
        XCTAssertFalse(menuSource.contains("TodoListContent"))
        XCTAssertFalse(chromeSource.contains("PopoverWindowTranslucencyConfigurator"))
        XCTAssertTrue(menuSource.contains("sidebarVisibility.toggleMenuTitle"))
        XCTAssertTrue(menuSource.contains("mainSectionVisibility.toggleMenuTitle"))
        XCTAssertTrue(menuSource.contains("Quit Akashic"))
    }

    func testMainWindowShowsCompletionBreathOverlay() throws {
        let mainSource = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Akashic/Views/MainWindowView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(mainSource.contains("CompletionBreathOverlay"))
        XCTAssertTrue(mainSource.contains("completionCelebrationID"))
    }

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
