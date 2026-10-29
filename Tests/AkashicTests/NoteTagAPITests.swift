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

    func testDecodeStringTagsRejectsOverMaxLengthViaAPIValidation() {
        let long = String(repeating: "x", count: 25)
        XCTAssertNotNil(NoteTagNormalization.apiTagNameLengthError(in: [long, "ok"]))
        let within = String(repeating: "y", count: 24)
        XCTAssertNil(NoteTagNormalization.apiTagNameLengthError(in: [within]))
    }

    func testDecodeStringTagsDefaultColor() {
        let tags = NoteTagAPIDecoding.decodeTags(from: ["alpha", "Beta", "alpha"])
        XCTAssertEqual(tags.map(\.name), ["alpha", "Beta"])
        XCTAssertTrue(tags.allSatisfy { $0.color == .defaultForNewTag })
    }

    func testDecodeMixedStringAndObjectTags() {
        let mixed: [Any] = [
            "plain",
            ["name": "colored", "color": "purple"],
            "plain",
        ]
        let tags = NoteTagAPIDecoding.decodeTags(from: mixed)
        XCTAssertEqual(tags.map(\.name), ["plain", "colored"])
        XCTAssertEqual(tags.first?.color, .defaultForNewTag)
        XCTAssertEqual(tags.last?.color, .purple)
    }

    func testParseStrictRejectsUnknownColor() {
        XCTAssertNil(AkashicTagColor.parseStrict("not-a-color"))
        XCTAssertEqual(AkashicTagColor.parseStrict("orange"), .orange)
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
