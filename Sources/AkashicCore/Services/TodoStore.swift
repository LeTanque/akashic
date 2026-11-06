import Combine
import Foundation
import GRDB

@MainActor
public final class TodoStore: ObservableObject {
    @Published public private(set) var todos: [TodoItem] = []
    @Published public var selectedTodoID: UUID?
    @Published public var lastImportMessage: String?
    @Published public private(set) var completionCelebrationID: UUID?
    @Published public private(set) var deletionCelebrationID: UUID?
    @Published public private(set) var revealTodoInListID: UUID?

    private let db: DatabaseQueue
    private var installation: InstallationContext

    public init() {
        db = (try? TodoDatabase.open()) ?? {
            fatalError("Failed to open Akashic database")
        }()
        installation = try! db.write { try InstallationContext.loadOrCreate(in: $0) }
        refresh()
        runFirstLaunchSeedIfNeeded()
    }

    /// Empty in-memory store for tests. Does not seed or start the HTTP API.
    public init(db: DatabaseQueue) {
        self.db = db
        installation = try! db.write { try InstallationContext.loadOrCreate(in: $0) }
        refresh()
    }

    /// Testing hook: empty in-memory database, no seed, no API server.
    public static func isolatedForTesting() throws -> TodoStore {
        try TodoStore(db: TodoDatabase.openInMemory())
    }

    public var selectedTodo: TodoItem? {
        guard let id = selectedTodoID else { return nil }
        return todos.first { $0.id == id }
    }

    public func refresh() {
        todos = (try? db.read { db in
            try TodoItem
                .filter(Column("deleted_at") == nil)
                .order(
                    TodoItem.Columns.completed.asc,
                    TodoItem.Columns.sortOrder.asc,
                    TodoItem.Columns.updatedAt.desc
                )
                .fetchAll(db)
        }) ?? []
        sortTodosInMemory()
    }

    /// Clears list selection so the editor shows an in-memory blank draft (no DB insert).
    public func beginNewTodoDraft() {
        selectedTodoID = nil
    }

    /// Legacy name used by menus; opens a blank draft without persisting.
    public func addTodo(title: String = "") {
        _ = title
        beginNewTodoDraft()
    }

    @discardableResult
    public func createTodo(
        title: String,
        description: String = "",
        priority: TodoPriority = .medium
    ) -> TodoItem {
        insertNewTodo(title: title, description: description, priority: priority)
    }

    /// Persists a new todo from the editor draft (single insert + order write).
    @discardableResult
    public func insertSavedTodo(from draft: TodoItem) -> TodoItem {
        insertNewTodo(
            title: draft.title,
            description: draft.description,
            priority: draft.priority,
            completeBy: draft.completeBy,
            completed: draft.completed,
            completedAt: draft.completedAt
        )
    }

    public func update(_ item: TodoItem) {
        guard let existing = todos.first(where: { $0.id == item.id }) else {
            persist(item, bumpUpdatedAt: true)
            return
        }
        var copy = item
        copy.sortOrder = existing.sortOrder
        persist(copy, bumpUpdatedAt: true)
    }

    public func delete(_ item: TodoItem) {
        _ = try? db.write { db in
            try self.softDeleteTodo(item.id, db: db)
        }
        if selectedTodoID == item.id {
            selectedTodoID = nil
        }
        refresh()
        deletionCelebrationID = UUID()
    }

    @discardableResult
    public func delete(id: UUID) -> Bool {
        guard let item = todos.first(where: { $0.id == id }) else { return false }
        delete(item)
        return true
    }

    public func toggleCompletion(for id: UUID) {
        guard var item = todos.first(where: { $0.id == id }) else { return }
        let wasCompleted = item.completed
        item.completed.toggle()
        item.updatedAt = Date()
        if item.completed {
            item.completedAt = Date()
        } else {
            item.completedAt = nil
        }
        persist(item, bumpUpdatedAt: false)
        if CompletionCelebration.shouldCelebrate(wasCompleted: wasCompleted, nowCompleted: item.completed) {
            triggerBreathingCelebration()
        }
    }

    /// Shared cyan border breathing effect (completion, successful todo Save, etc.).
    public func triggerBreathingCelebration() {
        completionCelebrationID = UUID()
    }

    public func revealTodoInList(_ id: UUID) {
        revealTodoInListID = id
    }

    public func todos(status: String) -> [TodoItem] {
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
    public func applyPatch(
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
            let wasCompleted = item.completed
            item.completed = completed
            item.completedAt = completed ? Date() : nil
            if CompletionCelebration.shouldCelebrate(wasCompleted: wasCompleted, nowCompleted: item.completed) {
                triggerBreathingCelebration()
            }
        }
        persist(item, bumpUpdatedAt: true)
        return todos.first { $0.id == id }
    }

    /// Drag-reorder within the currently displayed (possibly filtered) list.
    public func moveTodos(from source: IndexSet, to destination: Int, in displayed: [TodoItem]) {
        var reordered = displayed
        reordered.move(fromOffsets: source, toOffset: destination)
        applyManualOrder(reordered)
    }

    public func applyManualOrder(_ orderedSubset: [TodoItem]) {
        let incomplete = orderedSubset.filter { !$0.completed }
        let complete = orderedSubset.filter(\.completed)
        var next = todos
        next = Self.replacingRelativeOrder(in: next, with: incomplete)
        next = Self.replacingRelativeOrder(in: next, with: complete)
        writeOrder(next)
    }

    public func importSeedFromBundle(replaceExisting: Bool) {
        guard let data = SeedImporter.bundledSeedData() else {
            lastImportMessage = "Bundled seed file not found."
            return
        }
        importSeedData(data, replaceExisting: replaceExisting)
    }

    public func importSeedFromFile(url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            lastImportMessage = "Could not read \(url.lastPathComponent)."
            return
        }
        importSeedData(data, replaceExisting: true)
    }

    public func exportSeedJSON(source: String = "akashic export") throws -> Data {
        try SeedExporter.encodeJSON(from: todos, source: source)
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
        priority: TodoPriority = .medium,
        completeBy: Date? = nil,
        completed: Bool = false,
        completedAt: Date? = nil
    ) -> TodoItem {
        var item = installation.freshTodo(title: title, description: description, priority: priority)
        item.completeBy = completeBy
        item.completed = completed
        item.completedAt = completed ? (completedAt ?? Date()) : nil
        item.updatedAt = Date()
        var list = todos
        let index = Self.insertionIndex(for: item.priority, in: list)
        list.insert(item, at: index)
        let id = item.id
        writeOrder(list)
        return todos.first { $0.id == id } ?? item
    }

    public static func insertionIndex(for priority: TodoPriority, in items: [TodoItem]) -> Int {
        items.firstIndex {
            !$0.completed && $0.priority.sortOrder >= priority.sortOrder
        } ?? items.firstIndex(where: \.completed) ?? items.count
    }

    public static func replacingRelativeOrder(in items: [TodoItem], with orderedSubset: [TodoItem]) -> [TodoItem] {
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
                try self.persistTodo(&copy, bumpUpdatedAt: false, changedKeys: ["sort_order"], db: db)
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
            try self.persistTodo(&copy, bumpUpdatedAt: bumpUpdatedAt, changedKeys: nil, db: db)
        }
        refresh()
    }

    private func persistTodo(
        _ item: inout TodoItem,
        bumpUpdatedAt: Bool,
        changedKeys: Set<String>?,
        db: Database
    ) throws {
        let before = try TodoItem.fetchOne(db, key: item.id.uuidString)
        let clock = installation.tick()
        item.hlc = clock
        if bumpUpdatedAt {
            item.updatedAt = Date()
        }
        var keys = changedKeys
        if keys == nil {
            keys = diffTodoKeys(before: before, after: item)
        }
        for k in keys ?? [] {
            item.fieldClocks[k] = clock
        }
        item.version.set(clock)
        try item.save(db)
        let fc = fieldChangeMap(for: keys ?? [], clock: clock)
        try appendChangeLog(entity: .todo, recordID: item.id.uuidString, fields: fc, hlc: clock, db: db)
    }

    private func softDeleteTodo(_ id: UUID, db: Database) throws {
        guard var row = try TodoItem.fetchOne(db, key: id.uuidString) else { return }
        let clock = installation.tick()
        row.deletedAt = Date()
        row.hlc = clock
        row.fieldClocks["deleted_at"] = clock
        row.version.set(clock)
        try row.save(db)
        try appendChangeLog(entity: .todo, recordID: id.uuidString, fields: ["deleted_at": "\(clock.wallMillis)"], hlc: clock, db: db)
    }

    private func diffTodoKeys(before: TodoItem?, after: TodoItem) -> Set<String> {
        guard let before else {
            return ["title", "description", "completed", "priority", "complete_by", "completed_at", "sort_order"]
        }
        var keys = Set<String>()
        if before.title != after.title { keys.insert("title") }
        if before.description != after.description { keys.insert("description") }
        if before.completed != after.completed { keys.insert("completed") }
        if before.priority != after.priority { keys.insert("priority") }
        if before.completeBy != after.completeBy { keys.insert("complete_by") }
        if before.completedAt != after.completedAt { keys.insert("completed_at") }
        if before.sortOrder != after.sortOrder { keys.insert("sort_order") }
        return keys
    }

    private func fieldChangeMap(for keys: Set<String>, clock: HybridLogicalClock) -> [String: String] {
        var m: [String: String] = [:]
        for k in keys.sorted() {
            m[k] = "\(clock.wallMillis)-\(clock.counter)"
        }
        return m
    }

    private func appendChangeLog(entity: SyncEntity, recordID: String, fields: [String: String], hlc: HybridLogicalClock, db: Database) throws {
        guard !fields.isEmpty else { return }
        let entry = ChangeLogEntry(
            recordID: recordID,
            entity: entity,
            fieldChanges: fields,
            hlc: hlc,
            deviceID: installation.deviceId
        )
        try entry.insert(db)
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
