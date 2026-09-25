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
        let mortgage = try XCTUnwrap(items.first { $0.title.contains("Mortgage") })
        XCTAssertTrue(mortgage.completed)
        XCTAssertNotNil(mortgage.completedAt)
        let open = try XCTUnwrap(items.first { $0.title.contains("Pion prep") })
        XCTAssertFalse(open.completed)
        XCTAssertNil(open.completedAt)
    }
}
