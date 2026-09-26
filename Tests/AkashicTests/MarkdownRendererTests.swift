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

    func testParsesUnorderedList() {
        let attributed = MarkdownRenderer.attributedString(from: "- alpha\n- beta")
        XCTAssertTrue(containsList(attributed), "Expected an unordered list")
        XCTAssertTrue(String(attributed.characters).contains("alpha"))
        XCTAssertTrue(String(attributed.characters).contains("beta"))
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
}
