import Foundation
import GRDB
import SwiftUI

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [TodoItem] = []
    @Published var selectedTodoID: UUID?
    @Published var lastImportMessage: String?

    private let db: DatabaseQueue

    init() {
        db = (try? TodoDatabase.open()) ?? {
            fatalError("Failed to open Akashic database")
        }()
        refresh()
        runFirstLaunchSeedIfNeeded()
    }

    var selectedTodo: TodoItem? {
        guard let id = selectedTodoID else { return nil }
        return todos.first { $0.id == id }
    }

    func refresh() {
        todos = (try? db.read { db in
            try TodoItem
                .order(TodoItem.Columns.completed.asc, TodoItem.Columns.priority.asc, TodoItem.Columns.updatedAt.desc)
                .fetchAll(db)
        }) ?? []
        sortTodosInMemory()
    }

    func addTodo(title: String = "New todo") {
        var item = TodoItem.new(title: title)
        item.updatedAt = Date()
        persist(item)
    }

    func update(_ item: TodoItem) {
        var copy = item
        copy.updatedAt = Date()
        persist(copy)
    }

    func delete(_ item: TodoItem) {
        _ = try? db.write { db in
            try item.delete(db)
        }
        if selectedTodoID == item.id {
            selectedTodoID = nil
        }
        refresh()
    }

    func toggleCompletion(for id: UUID) {
        guard var item = todos.first(where: { $0.id == id }) else { return }
        item.completed.toggle()
        item.updatedAt = Date()
        if item.completed {
            item.completedAt = Date()
        } else {
            item.completedAt = nil
        }
        persist(item)
    }

    func importSeedFromBundle(replaceExisting: Bool) {
        guard let data = SeedImporter.bundledSeedData() else {
            lastImportMessage = "Bundled seed file not found."
            return
        }
        importSeedData(data, replaceExisting: replaceExisting)
    }

    func importSeedFromFile(url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            lastImportMessage = "Could not read \(url.lastPathComponent)."
            return
        }
        importSeedData(data, replaceExisting: true)
    }

    private func importSeedData(_ data: Data, replaceExisting: Bool) {
        do {
            let items = try SeedImporter.parseSeedData(data)
            let count = try SeedImporter.importItems(items, into: db, replaceExisting: replaceExisting)
            lastImportMessage = "Imported \(count) todos (expected \(items.count))."
            UserDefaults.standard.set(true, forKey: Self.seedImportDoneKey)
            refresh()
            if let first = todos.first {
                selectedTodoID = first.id
            }
        } catch {
            lastImportMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    private func persist(_ item: TodoItem) {
        try? db.write { db in
            try item.save(db)
        }
        refresh()
        if let idx = todos.firstIndex(where: { $0.id == item.id }) {
            todos[idx] = item
        }
    }

    private func runFirstLaunchSeedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.seedImportDoneKey) else { return }
        let count = (try? db.read { try TodoItem.fetchCount($0) }) ?? 0
        guard count == 0 else { return }
        importSeedFromBundle(replaceExisting: false)
    }

    private func sortTodosInMemory() {
        todos.sort { lhs, rhs in
            if lhs.completed != rhs.completed { return !lhs.completed && rhs.completed }
            if lhs.priority.sortOrder != rhs.priority.sortOrder {
                return lhs.priority.sortOrder < rhs.priority.sortOrder
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static let seedImportDoneKey = "akashic.seedImportDone"
}
