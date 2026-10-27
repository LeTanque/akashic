import XCTest
@testable import Akashic

final class SeedExporterTests: XCTestCase {
    func testExportImportRoundTripPreservesTitlesAndFlags() throws {
        let original = [
            TodoItem.new(title: "Alpha", priority: .high),
            TodoItem.new(title: "Beta", priority: .low),
        ]
        var completed = original[1]
        completed.completed = true
        completed.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        completed.completedAt = completed.updatedAt
        let todos = [original[0], completed]

        let data = try SeedExporter.encodeJSON(from: todos, source: "test export")
        let imported = try SeedImporter.parseSeedData(data)

        XCTAssertEqual(imported.count, 2)
        XCTAssertEqual(imported.map(\.title), ["Alpha", "Beta"])
        XCTAssertFalse(imported[0].completed)
        XCTAssertTrue(imported[1].completed)
        XCTAssertNotNil(imported[1].completedAt)
    }

    func testExportUsesSequentialNumericIds() throws {
        let todos = (0..<3).map { TodoItem.new(title: "Item \($0)") }
        let file = SeedExporter.exportFile(from: todos)
        XCTAssertEqual(file.todos.map(\.id), [1, 2, 3])
    }
}
