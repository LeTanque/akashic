import XCTest
@testable import Akashic

final class NoteTagAPITests: XCTestCase {
    func testDecodeObjectTags() {
        let json: [[String: Any]] = [
            ["name": " work ", "color": "orange"],
            ["name": "work", "color": "invalid"],
        ]
        let tags = NoteTagAPIDecoding.decodeTags(from: json)
        XCTAssertEqual(tags.map(\.name), ["work"])
        XCTAssertEqual(tags.first?.color, .orange)
    }

    func testDecodeStringTagsDefaultColor() {
        let tags = NoteTagAPIDecoding.decodeTags(from: ["alpha", "Beta", "alpha"])
        XCTAssertEqual(tags.map(\.name), ["alpha", "Beta"])
        XCTAssertTrue(tags.allSatisfy { $0.color == .defaultForNewTag })
    }

    func testNoteAPIDTOShape() throws {
        let note = NoteItem.new(
            title: "T",
            body: "B",
            tags: [AkashicTag(name: "work", color: .purple)]
        )
        let dto = NoteAPIDTO(note)
        let data = try JSONEncoder().encode(["note": dto])
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let noteObject = object?["note"] as? [String: Any]
        let tags = noteObject?["tags"] as? [[String: String]]
        XCTAssertEqual(tags?.first?["name"], "work")
        XCTAssertEqual(tags?.first?["color"], "purple")
    }
}
