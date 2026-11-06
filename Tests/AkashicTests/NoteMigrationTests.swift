import GRDB
import XCTest
@testable import Akashic

@MainActor
final class NoteMigrationTests: XCTestCase {
    func testCreateNotesMigrationPreservesExistingTodos() throws {
        let db = try TodoDatabase.openInMemory()
        try db.write { database in
            let inst = try InstallationContext.loadOrCreate(in: database)
            let c = inst.tick()
            var todo = TodoItem.unsavedDraft(title: "Survives migration", priority: .high)
            todo.hlc = c
            todo.fieldClocks = FieldClockMap(fields: [
                "title": c,
                "description": c,
                "completed": c,
                "priority": c,
                "complete_by": c,
                "completed_at": c,
                "sort_order": c,
            ])
            todo.version = VersionVector(map: [inst.deviceId: c])
            try todo.save(database)
        }

        let todoStore = TodoStore(db: db)
        let noteStore = NoteStore(db: db)

        XCTAssertEqual(todoStore.todos.count, 1)
        XCTAssertEqual(todoStore.todos.first?.title, "Survives migration")

        _ = noteStore.insertSavedNote(from: NoteItem.unsavedDraft(title: "Note one", body: "body"))
        XCTAssertEqual(todoStore.todos.count, 1)
        XCTAssertEqual(noteStore.notes.count, 1)
    }
}
