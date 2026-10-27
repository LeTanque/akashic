import XCTest
@testable import Akashic

@MainActor
final class NoteEditorSessionTests: XCTestCase {
    func testSelectNoteBlockedWhenDirty() throws {
        let store = try NoteStore.isolatedForTesting()
        let first = store.insertSavedNote(from: NoteItem.new(title: "One"))
        let second = store.insertSavedNote(from: NoteItem.new(title: "Two"))

        let session = NoteEditorSession { _ in .cancel }
        _ = session.selectNote(first, store: store)
        session.mutateForm { $0.draft.title = "Dirty" }

        XCTAssertFalse(session.selectNote(second, store: store))
        XCTAssertEqual(store.selectedNoteID, first.id)
    }

    func testSaveTriggersCelebrationID() throws {
        let store = try NoteStore.isolatedForTesting()
        let session = NoteEditorSession { _ in .save }
        session.mutateForm { form in
            form.draft.title = "Saved"
        }
        XCTAssertNil(store.completionCelebrationID)
        XCTAssertTrue(session.save(store: store))
        XCTAssertNotNil(store.completionCelebrationID)
    }
}
