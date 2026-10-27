import XCTest
@testable import Akashic

final class CompletionCheckboxTests: XCTestCase {
    func testCompletedStateUsesDeletionOrangeToken() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Akashic/Views/CompletionCheckbox.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("if completed"))
        XCTAssertTrue(source.contains("CyberpunkTheme.neonOrange"))
        XCTAssertFalse(source.contains("return CyberpunkTheme.neonCyan\n        }\n        if isHovered"))
    }
}
