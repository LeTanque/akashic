import Foundation
import GRDB

/// Test-only hooks (package tests). Must remain `nil` / `false` in production paths.
public enum TodoDatabaseTestingHooks {
    public nonisolated(unsafe) static var createEncryptedEmptyFailure: Error?
    public nonisolated(unsafe) static var openEncryptedFailure: Error?
    /// First `openEncrypted` throws this once, then behaves normally (tests rollback + retry).
    public nonisolated(unsafe) static var openEncryptedFailOnce: Error?
}

public enum TodoDatabase {
    /// Apply bundled schema migrations (used after `sqlcipher_export` and in tests).
    public static var migrator: DatabaseMigrator {
        Self.makeMigrator()
    }

    /// Live DB URL: `~/Library/Application Support/Akashic/akashic.sqlite` (or iOS equivalent).
    public static func databaseURL() throws -> URL {
        try AkashicPaths.databaseURL()
    }

    public static func encryptedConfiguration(passphrase: Data, label: String? = nil) -> Configuration {
        var config = Configuration()
        config.label = label ?? "AkashicEncrypted"
        config.prepareDatabase { db in
            try db.usePassphrase(passphrase)
        }
        return config
    }

    /// Opens the on-disk database with the SQLCipher data key, migrates, returns a queue.
    public static func openEncrypted(at url: URL, passphrase: Data) throws -> DatabaseQueue {
        if let once = TodoDatabaseTestingHooks.openEncryptedFailOnce {
            TodoDatabaseTestingHooks.openEncryptedFailOnce = nil
            throw once
        }
        if let err = TodoDatabaseTestingHooks.openEncryptedFailure {
            throw err
        }
        var config = encryptedConfiguration(passphrase: passphrase)
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try migrator.migrate(queue)
        return queue
    }

    /// Plain SQLite (legacy). Prefer only for reading pre-encryption files or in-memory tests.
    public static func openPlain(at url: URL) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: url.path)
        try migrator.migrate(queue)
        return queue
    }

    /// Creates a new empty encrypted database file (overwrites if caller removed existing temp).
    public static func createEncryptedEmpty(at url: URL, passphrase: Data) throws -> DatabaseQueue {
        if let err = TodoDatabaseTestingHooks.createEncryptedEmptyFailure {
            throw err
        }
        let queue = try DatabaseQueue(path: url.path, configuration: encryptedConfiguration(passphrase: passphrase))
        try migrator.migrate(queue)
        return queue
    }

    public static func openInMemory() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try migrator.migrate(queue)
        return queue
    }

    /// Open (and migrate) an existing SQLite file at `path`. Caller must use plain vs encrypted configuration.
    public static func open(at path: URL) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: path.path)
        try migrator.migrate(queue)
        return queue
    }

    private static func makeMigrator() -> DatabaseMigrator {
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
        migrator.registerMigration("createNotes") { db in
            try db.create(table: NoteItem.databaseTableName) { t in
                t.column(NoteItem.Columns.id.name, .text).primaryKey()
                t.column(NoteItem.Columns.title.name, .text).notNull()
                t.column(NoteItem.Columns.body.name, .text).notNull().defaults(to: "")
                t.column(NoteItem.Columns.createdAt.name, .datetime).notNull()
                t.column(NoteItem.Columns.updatedAt.name, .datetime).notNull()
            }
            try db.create(table: TagRecord.databaseTableName) { t in
                t.column(TagRecord.Columns.nameKey.name, .text).primaryKey()
                t.column(TagRecord.Columns.displayName.name, .text).notNull()
                t.column(TagRecord.Columns.color.name, .text).notNull()
                    .defaults(to: AkashicTagColor.defaultForNewTag.rawValue)
            }
            try db.create(table: NoteTagLinkRow.databaseTableName) { t in
                t.column(NoteTagLinkRow.Columns.noteID.name, .text)
                    .notNull()
                    .references(NoteItem.databaseTableName, onDelete: .cascade)
                t.column(NoteTagLinkRow.Columns.tagNameKey.name, .text)
                    .notNull()
                    .references(TagRecord.databaseTableName, onDelete: .cascade)
                t.primaryKey([
                    NoteTagLinkRow.Columns.noteID.name,
                    NoteTagLinkRow.Columns.tagNameKey.name,
                ])
            }
            try db.create(
                index: "idx_note_tags_tag_name_key",
                on: NoteTagLinkRow.databaseTableName,
                columns: [NoteTagLinkRow.Columns.tagNameKey.name]
            )
        }
        migrator.registerMigration("syncBookkeepingV1") { db in
            try db.create(table: AppMetaRecord.databaseTableName) { t in
                t.column(AppMetaRecord.Columns.key.name, .text).primaryKey()
                t.column(AppMetaRecord.Columns.value.name, .text).notNull()
            }
            try db.create(table: ChangeLogEntry.databaseTableName) { t in
                t.column(ChangeLogEntry.Columns.id.name, .text).primaryKey()
                t.column(ChangeLogEntry.Columns.recordID.name, .text).notNull()
                t.column(ChangeLogEntry.Columns.entity.name, .text).notNull()
                t.column(ChangeLogEntry.Columns.fieldChangesJSON.name, .text).notNull()
                t.column(ChangeLogEntry.Columns.hlcJSON.name, .text).notNull()
                t.column(ChangeLogEntry.Columns.deviceID.name, .text).notNull()
                t.column(ChangeLogEntry.Columns.createdAt.name, .datetime).notNull()
            }

            try db.alter(table: TodoItem.databaseTableName) { t in
                t.add(column: TodoItem.Columns.hlcJSON.name, .text).notNull().defaults(to: "{}")
                t.add(column: TodoItem.Columns.deletedAt.name, .datetime)
                t.add(column: TodoItem.Columns.fieldClocksJSON.name, .text).notNull().defaults(to: "{}")
                t.add(column: TodoItem.Columns.versionJSON.name, .text).notNull().defaults(to: "{}")
            }
            try db.alter(table: NoteItem.databaseTableName) { t in
                t.add(column: NoteItem.Columns.hlcJSON.name, .text).notNull().defaults(to: "{}")
                t.add(column: NoteItem.Columns.deletedAt.name, .datetime)
                t.add(column: NoteItem.Columns.fieldClocksJSON.name, .text).notNull().defaults(to: "{}")
                t.add(column: NoteItem.Columns.versionJSON.name, .text).notNull().defaults(to: "{}")
            }
            try db.alter(table: TagRecord.databaseTableName) { t in
                t.add(column: TagRecord.Columns.syncID.name, .text)
                t.add(column: TagRecord.Columns.hlcJSON.name, .text).notNull().defaults(to: "{}")
                t.add(column: TagRecord.Columns.deletedAt.name, .datetime)
                t.add(column: TagRecord.Columns.fieldClocksJSON.name, .text).notNull().defaults(to: "{}")
                t.add(column: TagRecord.Columns.versionJSON.name, .text).notNull().defaults(to: "{}")
            }
            try db.alter(table: NoteTagLinkRow.databaseTableName) { t in
                t.add(column: NoteTagLinkRow.Columns.hlcJSON.name, .text).notNull().defaults(to: "{}")
                t.add(column: NoteTagLinkRow.Columns.deletedAt.name, .datetime)
                t.add(column: NoteTagLinkRow.Columns.fieldClocksJSON.name, .text).notNull().defaults(to: "{}")
                t.add(column: NoteTagLinkRow.Columns.versionJSON.name, .text).notNull().defaults(to: "{}")
            }

            let installation = try InstallationContext.loadOrCreate(in: db)
            let deviceId = installation.deviceId
            let backfillClock = installation.clock.tick()
            let version = VersionVector(map: [deviceId: backfillClock])

            var todos = try TodoItem.fetchAll(db)
            for i in todos.indices {
                todos[i].hlc = backfillClock
                todos[i].deletedAt = nil
                todos[i].fieldClocks = FieldClockMap(fields: [
                    "title": backfillClock,
                    "description": backfillClock,
                    "completed": backfillClock,
                    "priority": backfillClock,
                    "complete_by": backfillClock,
                    "completed_at": backfillClock,
                    "sort_order": backfillClock,
                ])
                todos[i].version = version
                try todos[i].update(db)
            }

            var notes = try NoteItem.fetchAll(db)
            for i in notes.indices {
                notes[i].hlc = backfillClock
                notes[i].deletedAt = nil
                notes[i].fieldClocks = FieldClockMap(fields: [
                    "title": backfillClock,
                    "body": backfillClock,
                    "tags": backfillClock,
                ])
                notes[i].version = version
                try notes[i].update(db)
            }

            var tags = try TagRecord.fetchAll(db)
            for i in tags.indices {
                tags[i].syncId = tags[i].resolvedSyncId()
                tags[i].hlc = backfillClock
                tags[i].deletedAt = nil
                tags[i].fieldClocks = FieldClockMap(fields: [
                    "name": backfillClock,
                    "color": backfillClock,
                ])
                tags[i].version = version
                try tags[i].update(db)
            }

            var links = try NoteTagLinkRow.fetchAll(db)
            for i in links.indices {
                links[i].hlc = backfillClock
                links[i].deletedAt = nil
                links[i].fieldClocks = FieldClockMap(fields: [
                    "link": backfillClock,
                ])
                links[i].version = version
                try links[i].update(db)
            }

            installation.clock.receive(backfillClock)
        }
        return migrator
    }
}
