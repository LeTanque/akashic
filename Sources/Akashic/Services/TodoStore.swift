import Foundation
import GRDB
import SwiftUI

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var todos: [TodoItem] = []
    @Published var selectedTodoID: UUID?
    @Published var lastImportMessage: String?

    private let db: DatabaseQueue
    private let apiServer = TodoAPIServer()

    init() {
        db = (try? TodoDatabase.open()) ?? {
            fatalError("Failed to open Akashic database")
        }()
        refresh()
        runFirstLaunchSeedIfNeeded()
        apiServer.start(store: self)
    }

    /// Empty in-memory store for tests. Does not seed or start the HTTP API.
    init(db: DatabaseQueue) {
        self.db = db
        refresh()
    }

    /// Testing hook: empty in-memory database, no seed, no API server.
    static func isolatedForTesting() throws -> TodoStore {
        try TodoStore(db: TodoDatabase.openInMemory())
    }

    var selectedTodo: TodoItem? {
        guard let id = selectedTodoID else { return nil }
        return todos.first { $0.id == id }
    }

    func refresh() {
        todos = (try? db.read { db in
            try TodoItem
                .order(
                    TodoItem.Columns.completed.asc,
                    TodoItem.Columns.sortOrder.asc,
                    TodoItem.Columns.updatedAt.desc
                )
                .fetchAll(db)
        }) ?? []
        sortTodosInMemory()
    }

    func addTodo(title: String = "New todo") {
        let item = insertNewTodo(title: title)
        selectedTodoID = item.id
    }

    @discardableResult
    func createTodo(
        title: String,
        description: String = "",
        priority: TodoPriority = .medium
    ) -> TodoItem {
        insertNewTodo(title: title, description: description, priority: priority)
    }

    func update(_ item: TodoItem) {
        guard let existing = todos.first(where: { $0.id == item.id }) else {
            persist(item, bumpUpdatedAt: true)
            return
        }
        var copy = item
        copy.sortOrder = existing.sortOrder
        persist(copy, bumpUpdatedAt: true)
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

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard let item = todos.first(where: { $0.id == id }) else { return false }
        delete(item)
        return true
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
        persist(item, bumpUpdatedAt: false)
    }

    func todos(status: String) -> [TodoItem] {
        switch status.lowercased() {
        case "active":
            return todos.filter { !$0.completed }
        case "completed":
            return todos.filter(\.completed)
        default:
            return todos
        }
    }

    @discardableResult
    func applyPatch(
        id: UUID,
        title: String?,
        description: String?,
        completed: Bool?,
        priority: TodoPriority?,
        completeBy: Date?
    ) -> TodoItem? {
        guard var item = todos.first(where: { $0.id == id }) else { return nil }
        if let title { item.title = title }
        if let description { item.description = description }
        if let priority { item.priority = priority }
        if let completeBy { item.completeBy = completeBy }
        if let completed, item.completed != completed {
            item.completed = completed
            item.completedAt = completed ? Date() : nil
        }
        persist(item, bumpUpdatedAt: true)
        return todos.first { $0.id == id }
    }

    /// Drag-reorder within the currently displayed (possibly filtered) list.
    /// Completed items stay stacked after incomplete items; priority does not block the drop.
    func moveTodos(from source: IndexSet, to destination: Int, in displayed: [TodoItem]) {
        var reordered = displayed
        reordered.move(fromOffsets: source, toOffset: destination)
        applyManualOrder(reordered)
    }

    func applyManualOrder(_ orderedSubset: [TodoItem]) {
        let incomplete = orderedSubset.filter { !$0.completed }
        let complete = orderedSubset.filter(\.completed)
        var next = todos
        next = Self.replacingRelativeOrder(in: next, with: incomplete)
        next = Self.replacingRelativeOrder(in: next, with: complete)
        writeOrder(next)
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

    @discardableResult
    private func insertNewTodo(
        title: String,
        description: String = "",
        priority: TodoPriority = .medium
    ) -> TodoItem {
        var item = TodoItem.new(title: title, description: description, priority: priority)
        item.updatedAt = Date()
        var list = todos
        let index = Self.insertionIndex(for: item.priority, in: list)
        list.insert(item, at: index)
        let id = item.id
        writeOrder(list)
        return todos.first { $0.id == id } ?? item
    }

    /// Insert at the start of the matching priority band among incomplete items (high-first default).
    static func insertionIndex(for priority: TodoPriority, in items: [TodoItem]) -> Int {
        items.firstIndex {
            !$0.completed && $0.priority.sortOrder >= priority.sortOrder
        } ?? items.firstIndex(where: \.completed) ?? items.count
    }

    static func replacingRelativeOrder(in items: [TodoItem], with orderedSubset: [TodoItem]) -> [TodoItem] {
        guard !orderedSubset.isEmpty else { return items }
        let ids = Set(orderedSubset.map(\.id))
        var iterator = orderedSubset.makeIterator()
        return items.map { item in
            guard ids.contains(item.id), let replacement = iterator.next() else { return item }
            return replacement
        }
    }

    private func writeOrder(_ items: [TodoItem]) {
        try? db.write { db in
            for (index, item) in items.enumerated() {
                var copy = item
                copy.sortOrder = index
                try copy.save(db)
            }
        }
        refresh()
    }

    private func persist(_ item: TodoItem, bumpUpdatedAt: Bool) {
        var copy = item
        if bumpUpdatedAt {
            copy.updatedAt = Date()
        }
        try? db.write { db in
            try copy.save(db)
        }
        refresh()
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
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    private static let seedImportDoneKey = "akashic.seedImportDone"
}
