import Foundation
import GRDB

/// Migrates a legacy unencrypted `akashic.sqlite` into SQLCipher using `sqlcipher_export`.
public enum AkashicPlaintextMigration {
    /// First 16 bytes of a standard SQLite database file (ASCII).
    private static let sqliteMagic = "SQLite format 3\u{0}".data(using: .ascii)!

    public static func fileLooksLikePlaintextSQLite(at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let head = try handle.read(upToCount: 16), head.count == 16 else { return false }
        return head == sqliteMagic
    }

    public struct TableCounts: Equatable, Sendable {
        public var todos: Int
        public var notes: Int
        public var tags: Int
        public var noteTags: Int
        public var appMeta: Int
        public var changeLog: Int

        public init(
            todos: Int,
            notes: Int,
            tags: Int,
            noteTags: Int,
            appMeta: Int,
            changeLog: Int
        ) {
            self.todos = todos
            self.notes = notes
            self.tags = tags
            self.noteTags = noteTags
            self.appMeta = appMeta
            self.changeLog = changeLog
        }
    }

    public static func countRows(in db: Database) throws -> TableCounts {
        func countIfExists(_ table: String) throws -> Int {
            let exists = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS (SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?)",
                arguments: [table]
            ) ?? false
            guard exists else { return 0 }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
        }
        return TableCounts(
            todos: try countIfExists("todos"),
            notes: try countIfExists("notes"),
            tags: try countIfExists("tags"),
            noteTags: try countIfExists("note_tags"),
            appMeta: try countIfExists("app_meta"),
            changeLog: try countIfExists("change_log")
        )
    }

    /// Copies plaintext DB at `plaintextURL` into a new encrypted file at `encryptedDestinationURL` using `dataKey` as SQLCipher passphrase.
    /// Does not modify the plaintext file.
    public static func exportPlaintextToEncrypted(
        plaintextURL: URL,
        encryptedDestinationURL: URL,
        dataKey: Data
    ) throws {
        let plainConfig = Configuration()
        let plainQueue = try DatabaseQueue(path: plaintextURL.path, configuration: plainConfig)

        var encConfig = TodoDatabase.encryptedConfiguration(passphrase: dataKey)
        _ = FileManager.default.createFile(atPath: encryptedDestinationURL.path, contents: nil)
        let encQueue = try DatabaseQueue(path: encryptedDestinationURL.path, configuration: encConfig)

        let before = try plainQueue.read { try countRows(in: $0) }

        try plainQueue.write { db in
            try db.execute(
                sql: "ATTACH DATABASE ? AS encrypted KEY ?",
                arguments: [encryptedDestinationURL.path, dataKey]
            )
            try db.execute(sql: "SELECT sqlcipher_export('encrypted')")
            try db.execute(sql: "DETACH DATABASE encrypted")
        }

        let after = try encQueue.read { try countRows(in: $0) }
        guard before == after else {
            throw AkashicMigrationError.rowCountMismatch(expected: before, actual: after)
        }
        // Apply any pending GRDB migrations on the encrypted copy (usually no-op if source was current).
        try TodoDatabase.migrator.migrate(encQueue)
    }

    /// Backs up plaintext, replaces live DB with encrypted file atomically. Plaintext becomes `akashic.sqlite.plaintext-backup-<timestamp>`.
    public static func atomicSwapPlaintextForEncrypted(
        livePlaintextURL: URL,
        encryptedTempURL: URL,
        backupDirectory: URL
    ) throws {
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupName = "akashic.sqlite.plaintext-backup-\(ts)"
        let backupURL = backupDirectory.appendingPathComponent(backupName)

        guard FileManager.default.fileExists(atPath: encryptedTempURL.path) else {
            throw AkashicMigrationError.missingTempEncrypted
        }

        try FileManager.default.moveItem(at: livePlaintextURL, to: backupURL)

        do {
            try FileManager.default.moveItem(at: encryptedTempURL, to: livePlaintextURL)
        } catch {
            // Restore plaintext from backup so we never leave the user without a DB.
            try? FileManager.default.moveItem(at: backupURL, to: livePlaintextURL)
            throw error
        }
    }
}

public enum AkashicMigrationError: Error, Equatable, Sendable {
    case rowCountMismatch(expected: AkashicPlaintextMigration.TableCounts, actual: AkashicPlaintextMigration.TableCounts)
    case missingTempEncrypted
}
