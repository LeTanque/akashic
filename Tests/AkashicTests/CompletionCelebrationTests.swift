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
}
