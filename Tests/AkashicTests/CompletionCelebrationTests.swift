import XCTest
@testable import Akashic

@MainActor
final class CompletionCelebrationTests: XCTestCase {
    func testShouldCelebrateOnlyOnTransitionToCompleted() {
        XCTAssertTrue(CompletionCelebration.shouldCelebrate(wasCompleted: false, nowCompleted: true))
        XCTAssertFalse(CompletionCelebration.shouldCelebrate(wasCompleted: true, nowCompleted: true))
        XCTAssertFalse(CompletionCelebration.shouldCelebrate(wasCompleted: false, nowCompleted: false))
        XCTAssertFalse(CompletionCelebration.shouldCelebrate(wasCompleted: true, nowCompleted: false))
    }

    func testToggleCompletionToCompletePublishesCelebrationID() throws {
        let store = try TodoStore.isolatedForTesting()
        let item = store.createTodo(title: "Celebrate me")
        XCTAssertNil(store.completionCelebrationID)

        store.toggleCompletion(for: item.id)
        XCTAssertNotNil(store.completionCelebrationID)

        let first = store.completionCelebrationID
        store.toggleCompletion(for: item.id)
        XCTAssertEqual(store.completionCelebrationID, first)

        store.toggleCompletion(for: item.id)
        XCTAssertNotEqual(store.completionCelebrationID, first)
    }

    func testDeleteTodoPublishesDeletionCelebrationID() throws {
        let store = try TodoStore.isolatedForTesting()
        let item = store.createTodo(title: "Remove me")
        XCTAssertNil(store.deletionCelebrationID)

        XCTAssertTrue(store.delete(id: item.id))
        XCTAssertNotNil(store.deletionCelebrationID)
    }

    func testShouldCelebrateSuccessfulSaveOnlyWhenPersisted() {
        XCTAssertFalse(CompletionCelebration.shouldCelebrateSuccessfulSave(saveResult: nil))
        let id = UUID()
        XCTAssertTrue(
            CompletionCelebration.shouldCelebrateSuccessfulSave(saveResult: .created(id))
        )
        XCTAssertTrue(
            CompletionCelebration.shouldCelebrateSuccessfulSave(saveResult: .updated(id))
        )
    }

    func testSuccessfulFormSavePublishesBreathingCelebrationOnce() throws {
        let store = try TodoStore.isolatedForTesting()
        let session = TodoEditorSession()
        XCTAssertNil(store.completionCelebrationID)

        session.mutateForm { $0.draft.title = "Saved todo" }
        XCTAssertTrue(session.save(store: store))
        let first = try XCTUnwrap(store.completionCelebrationID)

        session.mutateForm { $0.draft.title = "   " }
        XCTAssertFalse(session.save(store: store))
        XCTAssertEqual(store.completionCelebrationID, first)

        session.mutateForm { $0.draft.title = "Another" }
        XCTAssertTrue(session.save(store: store))
        XCTAssertNotEqual(store.completionCelebrationID, first)
    }

    func testDiscardDoesNotPublishSaveCelebration() throws {
        let store = try TodoStore.isolatedForTesting()
        let item = store.createTodo(title: "Baseline")
        let session = TodoEditorSession()
        session.mutateForm { $0.load(item) }
        session.mutateForm { $0.draft.title = "Dirty" }
        session.mutateForm { $0.discard() }
        XCTAssertNil(store.completionCelebrationID)
    }
}
