import XCTest
@testable import Akashic

@MainActor
final class NoteStoreTests: XCTestCase {
    func testCRUDAndTagLinks() throws {
        let store = try NoteStore.isolatedForTesting()
        var draft = NoteItem.new(title: "First", body: "Body", tags: [
            AkashicTag(name: "work", color: .orange),
        ])
        let saved = store.insertSavedNote(from: draft)
        XCTAssertEqual(store.notes.count, 1)
        XCTAssertEqual(store.notes.first?.tags.map(\.name), ["work"])
        XCTAssertEqual(store.notes.first?.tags.first?.color, .orange)

        var edited = try XCTUnwrap(store.note(id: saved.id))
        edited.body = "Updated"
        edited.tags.append(AkashicTag(name: "ideas", color: .defaultForNewTag))
        store.update(edited)
        XCTAssertEqual(store.notes.first?.tags.count, 2)

        store.delete(saved)
        XCTAssertTrue(store.notes.isEmpty)
    }

    func testTagColorPersistsAndPropagatesToAllNotes() throws {
        let store = try NoteStore.isolatedForTesting()
        _ = store.insertSavedNote(from: NoteItem.new(
            title: "A",
            tags: [AkashicTag(name: "shared", color: .cyan)]
        ))
        _ = store.insertSavedNote(from: NoteItem.new(
            title: "B",
            tags: [AkashicTag(name: "shared", color: .cyan)]
        ))
        guard case .updated = store.setTagColor(name: "shared", color: .magenta) else {
            return XCTFail("Expected tag color update")
        }
        XCTAssertTrue(store.notes.allSatisfy { note in
            note.tags.first?.color == .magenta
        })
        XCTAssertEqual(store.allTagDefinitions().first?.color, .magenta)
    }

    func testFilterAndSort() throws {
        let store = try NoteStore.isolatedForTesting()
        _ = store.insertSavedNote(from: NoteItem.new(title: "Zebra", tags: [AkashicTag(name: "b")]))
        _ = store.insertSavedNote(from: NoteItem.new(title: "Alpha", tags: [AkashicTag(name: "a")]))
        let tagA = try XCTUnwrap(store.allTagDefinitions().first { $0.name == "a" })
        let filtered = store.filteredNotes(tag: tagA, sort: .titleAZ)
        XCTAssertEqual(filtered.map(\.title), ["Alpha"])
        let byTitle = store.filteredNotes(tag: nil, sort: .titleAZ)
        XCTAssertEqual(byTitle.map(\.title), ["Alpha", "Zebra"])
        let byTag = store.filteredNotes(tag: nil, sort: .tagAZ)
        XCTAssertEqual(byTag.first?.title, "Alpha")
    }

    func testSetTagColorReturnsNotFoundForUnknownTag() throws {
        let store = try NoteStore.isolatedForTesting()
        XCTAssertEqual(store.setTagColor(name: "missing", color: .red), .notFound)
        XCTAssertTrue(store.allTagDefinitions().isEmpty)
    }

    func testInsertSavedNoteSetsCreatedAtAtSaveTime() throws {
        let store = try NoteStore.isolatedForTesting()
        var draft = NoteItem.new(title: "Saved later", body: "")
        let stale = Date(timeIntervalSince1970: 1_000)
        draft.createdAt = stale
        draft.updatedAt = stale
        // DB dates are stored at millisecond precision, so allow 1 ms of truncation.
        let before = Date().addingTimeInterval(-0.001)
        let saved = store.insertSavedNote(from: draft)
        let after = Date().addingTimeInterval(0.001)
        XCTAssertGreaterThanOrEqual(saved.createdAt, before)
        XCTAssertLessThanOrEqual(saved.createdAt, after)
        XCTAssertNotEqual(saved.createdAt, stale)
    }

    func testNewNoteDraftDoesNotAppearUntilSaved() throws {
        let store = try NoteStore.isolatedForTesting()
        store.beginNewNoteDraft()
        XCTAssertNil(store.selectedNoteID)
        XCTAssertTrue(store.notes.isEmpty)
    }
}
