import XCTest
@testable import Akashic

@MainActor
final class TodoFormModelTests: XCTestCase {
    func testBlankDraftIsNotPersistedUntilSave() throws {
        let store = try TodoStore.isolatedForTesting()
        let initialCount = store.todos.count

        var form = TodoFormModel.blank()
        form.draft.title = "Draft only"
        XCTAssertTrue(form.isDirty)
        XCTAssertTrue(form.canSave)
        XCTAssertEqual(store.todos.count, initialCount)

        form.draft.title = "   "
        XCTAssertFalse(form.canSave)
        XCTAssertNil(form.save(into: store))

        form.reset()
        form.draft.title = "Ready"
        XCTAssertTrue(form.canSave)
        XCTAssertEqual(store.todos.count, initialCount)

        guard case .created(let newID) = form.save(into: store) else {
            return XCTFail("Expected created save result")
        }
        XCTAssertNotNil(store.todos.first { $0.id == newID })
        XCTAssertEqual(store.todos.count, initialCount + 1)
        XCTAssertTrue(form.isNew)
        XCTAssertFalse(form.isDirty)
    }

    func testCanSaveFalseForWhitespaceTitle() {
        var form = TodoFormModel.blank()
        form.draft.title = "   "
        XCTAssertFalse(form.canSave)
    }

    func testEditingSavedTodoDoesNotWriteUntilSave() throws {
        let store = try TodoStore.isolatedForTesting()
        let item = store.createTodo(title: "Original", description: "Body")
        var form = TodoFormModel.blank()
        form.load(item)

        form.draft.title = "Edited"
        XCTAssertTrue(form.isDirty)
        XCTAssertEqual(store.todos.first { $0.id == item.id }?.title, "Original")

        _ = form.save(into: store)
        XCTAssertEqual(store.todos.first { $0.id == item.id }?.title, "Edited")
        XCTAssertFalse(form.isDirty)
    }

    func testDiscardRestoresSavedBaseline() throws {
        let store = try TodoStore.isolatedForTesting()
        let item = store.createTodo(title: "Keep", description: "")
        var form = TodoFormModel.blank()
        form.load(item)
        form.draft.title = "Temporary"
        form.discard()
        XCTAssertEqual(form.draft.title, "Keep")
        XCTAssertFalse(form.isDirty)
    }

    func testUnsavedChangesGuard() {
        XCTAssertEqual(TodoFormModel.unsavedChangesGuard(isDirty: false), .allow)
        XCTAssertEqual(TodoFormModel.unsavedChangesGuard(isDirty: true), .needsConfirmation)
    }

    func testCompletionToggleOnSavedTodoWritesImmediately() throws {
        let store = try TodoStore.isolatedForTesting()
        let item = store.createTodo(title: "Toggle")
        store.toggleCompletion(for: item.id)
        XCTAssertTrue(store.todos.first { $0.id == item.id }?.completed ?? false)
    }
}
