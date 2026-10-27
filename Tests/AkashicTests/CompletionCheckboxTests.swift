import XCTest
@testable import Akashic

final class CompletionCheckboxTests: XCTestCase {
    func testListCompletionUsesCyanEditorBlockUsesOrange() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/CompletionCheckbox.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("case editorBlock"))
        XCTAssertTrue(source.contains("completedAccent"))
        XCTAssertTrue(source.contains("style == .editorBlock ? CyberpunkTheme.neonOrange : CyberpunkTheme.neonCyan"))
        XCTAssertTrue(source.contains("style == .list"))
    }
}
