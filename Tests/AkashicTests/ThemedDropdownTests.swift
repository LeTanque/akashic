import XCTest
@testable import Akashic

final class ThemedDropdownTests: XCTestCase {
    func testMainWindowFilterUsesThemedDropdownNotNativePicker() throws {
        let source = try mainWindowSource()
        XCTAssertTrue(source.contains("ThemedDropdown("))
        XCTAssertFalse(source.contains("pickerStyle(.menu)"))
    }

    func testPrioritySelectorUsesThemedDropdown() throws {
        let editor = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/Akashic/Views/TodoEditorView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(editor.contains("ThemedDropdown("))
        XCTAssertFalse(editor.contains("pickerStyle(.menu)"))
    }

    private func mainWindowSource() throws -> String {
        try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/Akashic/Views/MainWindowView.swift"),
            encoding: .utf8
        )
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
