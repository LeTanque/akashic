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

    func testTodoEditorCompleteByUsesSmallerThemedCheckbox() throws {
        let source = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/Akashic/Views/TodoEditorView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("themedCheckboxToggleStyle(checkboxSize: ThemedCheckboxMetrics.completeByEditor)"))
        XCTAssertTrue(source.contains("accessibilityLabel(\"Complete by\")"))
    }

    func testSettingsFocusUsesThemedRing() throws {
        let focusRing = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/Akashic/Views/Settings/AkashicSettingsFocusRing.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(focusRing.contains("focusEffectDisabled()"))

        let settings = try String(
            contentsOf: settingsViewSource(),
            encoding: .utf8
        )
        XCTAssertTrue(settings.contains("akashicSettingsFocusRing()"))
    }

    func testTodoEditorUsesThemedDueDatePickerNotNativeDatePicker() throws {
        let source = try String(
            contentsOf: sourceRoot().appendingPathComponent("Sources/Akashic/Views/TodoEditorView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("ThemedDueDatePicker"))
        let nativeDatePicker = try NSRegularExpression(pattern: "(?<![A-Za-z])DatePicker\\(")
        let range = NSRange(source.startIndex..., in: source)
        XCTAssertNil(nativeDatePicker.firstMatch(in: source, range: range))
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
