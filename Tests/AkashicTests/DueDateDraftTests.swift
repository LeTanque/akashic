import XCTest
@testable import Akashic

final class DueDateDraftTests: XCTestCase {
    func testSelectDoesNotChangeSaved() {
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        var draft = DueDateDraft(saved: saved)
        let pending = Date(timeIntervalSince1970: 1_800_000_000)
        draft.select(pending)
        XCTAssertEqual(draft.saved, saved)
        XCTAssertEqual(draft.pending, pending)
        XCTAssertTrue(draft.hasChanges)
    }

    func testCommitPersistsPendingOnce() {
        var draft = DueDateDraft(saved: nil)
        let pending = Date(timeIntervalSince1970: 1_800_000_000)
        draft.select(pending)
        let committed = draft.commit()
        XCTAssertEqual(committed, pending)
        XCTAssertEqual(draft.saved, pending)
        XCTAssertFalse(draft.hasChanges)
    }

    func testCancelDiscardsPending() {
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        var draft = DueDateDraft(saved: saved)
        draft.select(Date(timeIntervalSince1970: 1_900_000_000))
        draft.cancel()
        XCTAssertEqual(draft.pending, saved)
        XCTAssertFalse(draft.hasChanges)
    }

    func testClearPendingCommittedOnSave() {
        let saved = Date(timeIntervalSince1970: 1_700_000_000)
        var draft = DueDateDraft(saved: saved)
        draft.clearPending()
        XCTAssertTrue(draft.hasChanges)
        let committed = draft.commit()
        XCTAssertNil(committed)
        XCTAssertNil(draft.saved)
    }

    func testSyncSavedResetsPending() {
        var draft = DueDateDraft(saved: Date(timeIntervalSince1970: 1_000))
        draft.select(Date(timeIntervalSince1970: 2_000))
        let external = Date(timeIntervalSince1970: 3_000)
        draft.syncSaved(external)
        XCTAssertEqual(draft.saved, external)
        XCTAssertEqual(draft.pending, external)
        XCTAssertFalse(draft.hasChanges)
    }
}
