import XCTest
@testable import Akashic

final class ThemedCheckboxTests: XCTestCase {
    func testSettingsAppearanceUsesThemedCheckbox() throws {
        let source = try String(
            contentsOf: settingsViewSource(),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("themedCheckboxToggleStyle"))
        XCTAssertFalse(source.contains(".toggleStyle(.checkbox)"))
    }

    func testTodoEditorUsesThemedDueDatePickerNotNativeDatePicker() throws {
        let source = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/Akashic/Views/TodoEditorView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("ThemedDueDatePicker"))
        XCTAssertFalse(source.contains("DatePicker("))
    }

    private func settingsViewSource() -> URL {
        sourceRoot().appendingPathComponent("Sources/Akashic/Views/Settings/AkashicSettingsView.swift")
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
