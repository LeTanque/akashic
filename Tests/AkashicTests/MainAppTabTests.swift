import XCTest
@testable import Akashic

final class MainAppTabTests: XCTestCase {
    func testDefaultWorkspaceTabIsTodos() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Akashic/Views/MainWindowView.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(
            source.contains("@State private var workspaceTab: MainAppTab = .todos"),
            "Launch default tab must remain Todos for the session"
        )
    }

    func testTabBarAboveHeaderStrip() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Akashic/Views/MainWindowView.swift"),
            encoding: .utf8
        )
        guard let tabRange = source.range(of: "MainWorkspaceTabBar"),
              let headerRange = source.range(of: "CyberHeaderStrip")
        else {
            return XCTFail("Expected tab bar and header in MainWindowView")
        }
        XCTAssertTrue(tabRange.lowerBound < headerRange.lowerBound)
    }
}
