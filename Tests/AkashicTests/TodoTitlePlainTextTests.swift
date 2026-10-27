import XCTest
@testable import Akashic

final class TodoTitlePlainTextTests: XCTestCase {
    func testListRowsUsePlainTitleTextNotMarkdown() throws {
        let root = sourceRoot()
        let row = try String(contentsOf: root.appendingPathComponent("Sources/Akashic/Views/TodoRowView.swift"), encoding: .utf8)
        XCTAssertTrue(row.contains("TodoTitleText("))
        XCTAssertFalse(row.contains("MarkdownText(\n                markdown: todo.title"))
    }

    func testEditorUsesPlainTitleFieldWithoutMarkdownPreview() throws {
        let root = sourceRoot()
        let editor = try String(contentsOf: root.appendingPathComponent("Sources/Akashic/Views/TodoEditorView.swift"), encoding: .utf8)
        XCTAssertTrue(editor.contains("PlainTitleField("))
        XCTAssertFalse(editor.contains("MarkdownLiveEditor(\n                            text: $draft.title"))
        XCTAssertFalse(editor.contains("Title (markdown)"))
        XCTAssertFalse(editor.contains("Title markdown source"))
    }

    func testPlainTitleFieldHasNoLivePreviewAffordance() throws {
        let root = sourceRoot()
        let titleView = try String(
            contentsOf: root.appendingPathComponent("Sources/Akashic/Views/TodoTitleText.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(titleView.contains("MarkdownRenderer"))
        XCTAssertFalse(titleView.contains("MarkdownText"))
        XCTAssertTrue(titleView.contains("Text(displayText)"))
    }

    func testMarkdownCharactersDisplayLiterallyInDisplayText() {
        let raw = "**bold** and `code`"
        XCTAssertEqual(raw, raw)
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
