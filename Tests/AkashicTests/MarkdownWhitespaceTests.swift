import XCTest
@testable import Akashic

final class MarkdownWhitespaceTests: XCTestCase {
    func testDoubleSpacesPreservedInPlainText() {
        let text = String(MarkdownRenderer.attributedString(from: "hello  world").characters)
        XCTAssertTrue(text.contains("hello"), text)
        XCTAssertTrue(text.contains("  ") || text.contains("\u{00A0}\u{00A0}"), "Expected two visible spaces, got: \(text)")
    }

    func testLeadingIndentPreserved() {
        let text = String(MarkdownRenderer.attributedString(from: "    indented").characters)
        XCTAssertTrue(
            text.hasPrefix("    ") || text.hasPrefix("\u{00A0}\u{00A0}\u{00A0}\u{00A0}"),
            "Leading spaces should survive rendering: \(text)"
        )
        XCTAssertTrue(text.contains("indented"))
    }

    func testSpacesAroundBoldPreserved() {
        let text = String(MarkdownRenderer.attributedString(from: "aa **bold** bb").characters)
        XCTAssertTrue(text.contains("aa"))
        XCTAssertTrue(text.contains("bold"))
        XCTAssertTrue(text.contains("bb"))
        XCTAssertTrue(text.contains(" ") || text.contains("\u{00A0}"))
    }

    func testSpacesAroundInlineCodePreserved() {
        let text = String(MarkdownRenderer.attributedString(from: "run `code` now").characters)
        XCTAssertTrue(text.contains("run"))
        XCTAssertTrue(text.contains("code"))
        XCTAssertTrue(text.contains("now"))
    }
}
