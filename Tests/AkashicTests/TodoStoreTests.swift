import XCTest
@testable import Akashic

@MainActor
final class TodoStoreTests: XCTestCase {
    func testAddTodoSelectsTheNewItem() throws {
        let store = try TodoStore.isolatedForTesting()
        store.createTodo(title: "Existing", priority: .high)
        store.addTodo(title: "Brand new")
        XCTAssertEqual(store.selectedTodo?.title, "Brand new")
    }

    func testCreateTodoDoesNotStealSelection() throws {
        let store = try TodoStore.isolatedForTesting()
        store.addTodo(title: "Selected")
        let selected = try XCTUnwrap(store.selectedTodoID)
        store.createTodo(title: "Via API", priority: .high)
        XCTAssertEqual(store.selectedTodoID, selected)
    }

    func testDefaultInsertOrderIsHighFirst() throws {
        let store = try TodoStore.isolatedForTesting()
        store.createTodo(title: "Low", priority: .low)
        store.createTodo(title: "High", priority: .high)
        store.createTodo(title: "Medium", priority: .medium)
        XCTAssertEqual(store.todos.map(\.title), ["High", "Medium", "Low"])
        XCTAssertEqual(store.todos.map(\.priority), [.high, .medium, .low])
    }

    func testNewHighInsertsAtTopOfIncomplete() throws {
        let store = try TodoStore.isolatedForTesting()
        store.createTodo(title: "Older high", priority: .high)
        store.createTodo(title: "Medium", priority: .medium)
        store.createTodo(title: "Newest high", priority: .high)
        XCTAssertEqual(store.todos.map(\.title), ["Newest high", "Older high", "Medium"])
    }

    func testUpdateDoesNotChangeListOrder() throws {
        let store = try TodoStore.isolatedForTesting()
        let high = store.createTodo(title: "H", priority: .high)
        let medium = store.createTodo(title: "M", priority: .medium)
        let idsBefore = store.todos.map(\.id)
        var edited = medium
        edited.title = "M2"
        store.update(edited)
        XCTAssertEqual(store.todos.map(\.id), idsBefore)
        XCTAssertEqual(store.todos.first { $0.id == medium.id }?.sortOrder, medium.sortOrder)
        XCTAssertEqual(store.todos.first { $0.id == high.id }?.title, "H")
        XCTAssertEqual(store.todos.first { $0.id == medium.id }?.title, "M2")
    }

    func testManualReorderCanPlaceLowAboveHigh() throws {
        let store = try TodoStore.isolatedForTesting()
        store.createTodo(title: "H", priority: .high)
        store.createTodo(title: "L", priority: .low)
        XCTAssertEqual(store.todos.map(\.title), ["H", "L"])
        store.moveTodos(from: IndexSet(integer: 1), to: 0, in: store.todos)
        XCTAssertEqual(store.todos.map(\.title), ["L", "H"])
        XCTAssertEqual(store.todos.map(\.priority), [.low, .high])
    }

    func testCompletedStayLastAfterAttemptedMoveToTop() throws {
        let store = try TodoStore.isolatedForTesting()
        let high = store.createTodo(title: "A", priority: .high)
        store.createTodo(title: "B", priority: .medium)
        store.toggleCompletion(for: high.id)
        XCTAssertEqual(store.todos.map(\.title), ["B", "A"])
        XCTAssertTrue(store.todos.last?.completed ?? false)

        store.moveTodos(from: IndexSet(integer: 1), to: 0, in: store.todos)
        XCTAssertEqual(store.todos.first?.title, "B")
        XCTAssertTrue(store.todos.last?.id == high.id)
        XCTAssertTrue(store.todos.last?.completed ?? false)
    }

    func testPriorityChangeDoesNotRestack() throws {
        let store = try TodoStore.isolatedForTesting()
        store.createTodo(title: "H", priority: .high)
        let low = store.createTodo(title: "L", priority: .low)
        store.moveTodos(from: IndexSet(integer: 1), to: 0, in: store.todos)
        XCTAssertEqual(store.todos.map(\.title), ["L", "H"])

        var edited = try XCTUnwrap(store.todos.first { $0.id == low.id })
        edited.priority = .high
        store.update(edited)
        XCTAssertEqual(store.todos.map(\.title), ["L", "H"])
        XCTAssertEqual(store.todos.first?.priority, .high)
    }

    func testImportAssignsHighFirstSortOrder() throws {
        let store = try TodoStore.isolatedForTesting()
        store.importSeedFromBundle(replaceExisting: true)
        let open = store.todos.filter { !$0.completed }
        let priorityRanks = open.map(\.priority.sortOrder)
        XCTAssertEqual(priorityRanks, priorityRanks.sorted())
        XCTAssertTrue(store.todos.drop(while: { !$0.completed }).allSatisfy(\.completed))
        XCTAssertGreaterThanOrEqual(store.todos.count, 12)
    }

    func testDefaultStackOrderHighFirst() {
        let high = TodoItem.new(title: "h", priority: .high)
        var low = TodoItem.new(title: "l", priority: .low)
        low.updatedAt = high.updatedAt.addingTimeInterval(10)
        XCTAssertTrue(TodoItem.defaultStackOrder(high, low))
        XCTAssertFalse(TodoItem.defaultStackOrder(low, high))

        var completedHigh = TodoItem.new(title: "done", priority: .high)
        completedHigh.completed = true
        XCTAssertTrue(TodoItem.defaultStackOrder(low, completedHigh))
    }

    func testInsertionIndexPlacesMediumAfterHighs() {
        let high = TodoItem.new(title: "H", priority: .high)
        let low = TodoItem.new(title: "L", priority: .low)
        let items = [high, low]
        XCTAssertEqual(TodoStore.insertionIndex(for: .medium, in: items), 1)
        XCTAssertEqual(TodoStore.insertionIndex(for: .high, in: items), 0)
        XCTAssertEqual(TodoStore.insertionIndex(for: .low, in: items), 1)
    }

    func testUpdatePersistsMarkdownDescriptionSourceUnchanged() throws {
        let store = try TodoStore.isolatedForTesting()
        let item = store.createTodo(title: "Note", description: "")
        let source = """
        # Heading
        See **bold**, *italic*, `code`, and [docs](https://example.com).
        - list item
        """
        var edited = item
        edited.description = source
        store.update(edited)
        XCTAssertEqual(store.todos.first { $0.id == item.id }?.description, source)
        XCTAssertEqual(store.todos.first { $0.id == item.id }?.title, "Note")
    }

    func testHasSameEditableContentIgnoresTimestampsAndSortOrder() {
        var a = TodoItem.new(title: "Same", description: "D", priority: .medium)
        var b = a
        b.updatedAt = a.updatedAt.addingTimeInterval(5)
        b.sortOrder = 9
        XCTAssertTrue(a.hasSameEditableContent(as: b))
        b.title = "Other"
        XCTAssertFalse(a.hasSameEditableContent(as: b))
    }
}
