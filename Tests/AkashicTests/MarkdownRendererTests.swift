import SwiftUI
import XCTest
@testable import Akashic

final class MarkdownRendererTests: XCTestCase {
    func testEmptyStringRendersEmpty() {
        let attributed = MarkdownRenderer.attributedString(from: "")
        XCTAssertEqual(String(attributed.characters), "")
    }

    func testPlainTextRoundTrips() {
        let attributed = MarkdownRenderer.attributedString(from: "just words")
        XCTAssertEqual(String(attributed.characters), "just words")
    }

    func testParsesStrongEmphasis() {
        let attributed = MarkdownRenderer.attributedString(from: "say **bold** now")
        XCTAssertTrue(
            containsInlineIntent(attributed, .stronglyEmphasized),
            "Expected **bold** to mark stronglyEmphasized"
        )
        XCTAssertTrue(String(attributed.characters).contains("bold"))
    }

    func testParsesEmphasis() {
        let attributed = MarkdownRenderer.attributedString(from: "say *italic* now")
        XCTAssertTrue(
            containsInlineIntent(attributed, .emphasized),
            "Expected *italic* to mark emphasized"
        )
    }

    func testParsesInlineCode() {
        let attributed = MarkdownRenderer.attributedString(from: "run `ls -la` please")
        XCTAssertTrue(
            containsInlineIntent(attributed, .code),
            "Expected `code` to mark inline code"
        )
        XCTAssertTrue(
            hasBackground(on: attributed, containing: "ls"),
            "Inline code must get a visible background, not only a code intent"
        )
    }

    func testParsesLink() throws {
        let attributed = MarkdownRenderer.attributedString(from: "See [docs](https://example.com/path).")
        let urls = attributed.runs[\.link].compactMap(\.0)
        let url = try XCTUnwrap(urls.first)
        XCTAssertEqual(url.host, "example.com")
        XCTAssertTrue(String(attributed.characters).contains("docs"))
    }

    func testParsesHeading() {
        let attributed = MarkdownRenderer.attributedString(from: "# Title\n\nBody")
        XCTAssertTrue(containsHeader(attributed, level: 1), "Expected a level-1 heading")
        XCTAssertTrue(String(attributed.characters).contains("Title"))
    }

    func testHeadingAppliesVisibleTypographyNotOnlyPresentationIntent() {
        let attributed = MarkdownRenderer.attributedString(from: "# Title\n\nBody")
        XCTAssertTrue(containsHeader(attributed, level: 1))
        XCTAssertTrue(
            headingLooksVisible(attributed, text: "Title"),
            "Heading must carry bold/font so SwiftUI Text can show it; presentationIntent alone is not enough"
        )
        XCTAssertFalse(
            headingLooksVisible(attributed, text: "Body"),
            "Body copy next to a heading must stay unemphasized"
        )
    }

    func testParsesUnorderedList() {
        let attributed = MarkdownRenderer.attributedString(from: "- alpha\n- beta")
        XCTAssertTrue(containsList(attributed), "Expected an unordered list")
        XCTAssertTrue(String(attributed.characters).contains("alpha"))
        XCTAssertTrue(String(attributed.characters).contains("beta"))
    }

    func testUnorderedListInsertsVisibleBulletGlyphs() {
        let attributed = MarkdownRenderer.attributedString(from: "- alpha\n- beta")
        let text = String(attributed.characters)
        let bullets = text.filter { $0 == MarkdownRenderer.unorderedListBullet }
        XCTAssertGreaterThanOrEqual(
            bullets.count,
            2,
            "List items must get visible bullet glyphs, not only presentationIntent"
        )
        XCTAssertTrue(text.contains("alpha"))
        XCTAssertTrue(text.contains("beta"))

        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.isEmpty }
        XCTAssertGreaterThanOrEqual(lines.count, 2, "List items must wrap onto separate lines")
    }

    func testAsteriskAndPlusListsAlsoGetBullets() {
        for source in ["* alpha\n* beta", "+ alpha\n+ beta"] {
            let text = String(MarkdownRenderer.attributedString(from: source).characters)
            let bullets = text.filter { $0 == MarkdownRenderer.unorderedListBullet }
            XCTAssertGreaterThanOrEqual(bullets.count, 2, "Failed for \(source)")
        }
    }

    func testOrderedListInsertsVisibleOrdinals() {
        let text = String(MarkdownRenderer.attributedString(from: "1. first\n2. second").characters)
        XCTAssertTrue(text.contains("1."), "Ordered items must show an ordinal, not only list intent")
        XCTAssertTrue(text.contains("2."))
        XCTAssertTrue(text.contains("first"))
        XCTAssertTrue(text.contains("second"))
    }

    func testNestedListKeepsBothItemsVisible() {
        let text = String(MarkdownRenderer.attributedString(from: "- parent\n  - child").characters)
        XCTAssertTrue(text.contains("parent"))
        XCTAssertTrue(text.contains("child"))
        XCTAssertGreaterThanOrEqual(
            text.filter { $0 == MarkdownRenderer.unorderedListBullet }.count,
            2
        )
    }

    func testSmartDashListMarkersStillRenderAsLists() {
        let source = "\u{2013} alpha\n\u{2014} beta"
        XCTAssertEqual(
            MarkdownRenderer.normalizeSmartTypography(source),
            "- alpha\n- beta"
        )
        let attributed = MarkdownRenderer.attributedString(from: source)
        let text = String(attributed.characters)
        XCTAssertGreaterThanOrEqual(
            text.filter { $0 == MarkdownRenderer.unorderedListBullet }.count,
            2,
            "En/em-dash line prefixes from macOS smart substitution must still become visible lists"
        )
        XCTAssertTrue(containsList(attributed))
    }

    func testMidLineEnDashIsNotTreatedAsAListMarker() {
        XCTAssertEqual(
            MarkdownRenderer.normalizeSmartTypography("keep \u{2013} mid"),
            "keep \u{2013} mid"
        )
        let text = String(MarkdownRenderer.attributedString(from: "keep \u{2013} mid").characters)
        XCTAssertTrue(text.contains("keep"))
        XCTAssertTrue(text.contains("mid"))
        XCTAssertFalse(text.contains(String(MarkdownRenderer.unorderedListBullet)))
    }

    func testIncompleteMarkupStillReturnsText() {
        let attributed = MarkdownRenderer.attributedString(from: "Hello **unclosed")
        XCTAssertFalse(String(attributed.characters).isEmpty)
        XCTAssertTrue(String(attributed.characters).contains("Hello"))
    }

    func testSourceStringIsNotMutated() {
        var source = "Keep **this** source"
        _ = MarkdownRenderer.attributedString(from: source)
        XCTAssertEqual(source, "Keep **this** source")
    }

    func testTitleEditorUsesLiveMarkdownSourceNotSwiftUITextEditor() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let editor = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Views/TodoEditorView.swift"),
            encoding: .utf8
        )
        let live = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Views/MarkdownDescriptionEditor.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            editor.contains("TextEditor(text: $draft.title)"),
            "SwiftUI TextEditor applies smart dashes that break CommonMark `- ` lists"
        )
        XCTAssertTrue(editor.contains("Title markdown source"))
        XCTAssertTrue(editor.contains("MarkdownLiveEditor"))
        XCTAssertTrue(live.contains("isAutomaticDashSubstitutionEnabled = false"))
        XCTAssertTrue(live.contains("isAutomaticQuoteSubstitutionEnabled = false"))
        XCTAssertTrue(live.contains("MarkdownText("))
    }

    private func containsInlineIntent(
        _ attributed: AttributedString,
        _ intent: InlinePresentationIntent
    ) -> Bool {
        attributed.runs[\.inlinePresentationIntent].contains { value, _ in
            guard let value else { return false }
            return value.contains(intent)
        }
    }

    private func containsHeader(_ attributed: AttributedString, level: Int) -> Bool {
        attributed.runs[\.presentationIntent].contains { intent, _ in
            guard let intent else { return false }
            return intent.components.contains { component in
                if case .header(let headerLevel) = component.kind {
                    return headerLevel == level
                }
                return false
            }
        }
    }

    private func containsList(_ attributed: AttributedString) -> Bool {
        attributed.runs[\.presentationIntent].contains { intent, _ in
            guard let intent else { return false }
            return intent.components.contains { component in
                switch component.kind {
                case .unorderedList, .orderedList, .listItem:
                    return true
                default:
                    return false
                }
            }
        }
    }

    private func headingLooksVisible(_ attributed: AttributedString, text needle: String) -> Bool {
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            guard text.contains(needle) else { continue }
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                return true
            }
            if run.font != nil {
                return true
            }
        }
        return false
    }

    private func hasBackground(on attributed: AttributedString, containing needle: String) -> Bool {
        attributed.runs[\.backgroundColor].contains { color, range in
            guard color != nil else { return false }
            return String(attributed[range].characters).contains(needle)
        }
    }
}
