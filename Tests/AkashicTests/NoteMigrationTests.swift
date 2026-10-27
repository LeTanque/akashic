import GRDB
import XCTest
@testable import Akashic

final class NoteMigrationTests: XCTestCase {
    func testCreateNotesMigrationPreservesExistingTodos() throws {
        let db = try TodoDatabase.openInMemory()
        var todo = TodoItem.new(title: "Survives migration", priority: .high)
        try db.write { try todo.save($0) }

        let todoStore = TodoStore(db: db)
        let noteStore = NoteStore(db: db)

        XCTAssertEqual(todoStore.todos.count, 1)
        XCTAssertEqual(todoStore.todos.first?.title, "Survives migration")

        _ = noteStore.insertSavedNote(from: NoteItem.new(title: "Note one", body: "body"))
        XCTAssertEqual(todoStore.todos.count, 1)
        XCTAssertEqual(noteStore.notes.count, 1)
    }
}
