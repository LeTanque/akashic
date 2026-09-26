import Foundation
import GRDB

enum TodoDatabase {
    static func open() throws -> DatabaseQueue {
        let url = try databaseURL()
        let queue = try DatabaseQueue(path: url.path)
        try migrator.migrate(queue)
        return queue
    }

    /// Empty on-disk-less database for unit tests. Applies the same migrations as the live DB.
    static func openInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try migrator.migrate(queue)
        return queue
    }

    private static func databaseURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = appSupport.appendingPathComponent("Akashic", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("akashic.sqlite")
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("createTodos") { db in
            try db.create(table: TodoItem.databaseTableName) { t in
                t.column(TodoItem.Columns.id.name, .text).primaryKey()
                t.column(TodoItem.Columns.title.name, .text).notNull()
                t.column(TodoItem.Columns.description.name, .text).notNull().defaults(to: "")
                t.column(TodoItem.Columns.completed.name, .boolean).notNull().defaults(to: false)
                t.column(TodoItem.Columns.priority.name, .text).notNull().defaults(to: TodoPriority.medium.rawValue)
                t.column(TodoItem.Columns.completeBy.name, .datetime)
                t.column(TodoItem.Columns.createdOn.name, .datetime).notNull()
                t.column(TodoItem.Columns.updatedAt.name, .datetime).notNull()
                t.column(TodoItem.Columns.completedAt.name, .datetime)
            }
        }
        migrator.registerMigration("addSortOrder") { db in
            try db.alter(table: TodoItem.databaseTableName) { t in
                t.add(column: TodoItem.Columns.sortOrder.name, .integer).notNull().defaults(to: 0)
            }
            let items = try TodoItem.fetchAll(db)
            let ordered = items.sorted(by: TodoItem.defaultStackOrder)
            for (index, item) in ordered.enumerated() {
                try db.execute(
                    sql: "UPDATE \(TodoItem.databaseTableName) SET sort_order = ? WHERE id = ?",
                    arguments: [index, item.id.uuidString]
                )
            }
        }
        return migrator
    }
}
