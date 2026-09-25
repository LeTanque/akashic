import XCTest
@testable import Akashic

final class SeedImporterTests: XCTestCase {
    func testBundledSeedHasTwelveTodos() throws {
        let data = try XCTUnwrap(SeedImporter.bundledSeedData())
        let items = try SeedImporter.parseSeedData(data)
        XCTAssertEqual(items.count, 12)
    }

    func testCompletedTodosGetCompletedAtFromUpdatedAt() throws {
        let data = try XCTUnwrap(SeedImporter.bundledSeedData())
        let items = try SeedImporter.parseSeedData(data)
        let completed = try XCTUnwrap(items.first { $0.title.contains("Example completed") })
        XCTAssertTrue(completed.completed)
        XCTAssertNotNil(completed.completedAt)
        let open = try XCTUnwrap(items.first { $0.title.contains("Welcome to Akashic") })
        XCTAssertFalse(open.completed)
        XCTAssertNil(open.completedAt)
    }
}
