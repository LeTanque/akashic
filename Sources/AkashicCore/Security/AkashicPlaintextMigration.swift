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
        if let err = AkashicPlaintextMigrationTestingHooks.exportPlaintextFailure {
            throw err
        }
        guard !dataKey.isEmpty else { throw AkashicCryptoError.invalidInput }

        let plainConfig = Configuration()
        let plainQueue = try DatabaseQueue(path: plaintextURL.path, configuration: plainConfig)
        let before = try plainQueue.read { try countRows(in: $0) }
        // Merge WAL into the main file; abort if another writer leaves WAL busy or non-empty.
        try plainQueue.write { db in
            try SQLiteDiskBundle.requireTruncatingWalCheckpointIfWAL(db)
        }
        // Drop our reader so ATTACH below is the only connection on the plaintext file.
        // (Callers must also release any other open queues on `plaintextURL`.)
        try plainQueue.close()

        if FileManager.default.fileExists(atPath: encryptedDestinationURL.path) {
            try FileManager.default.removeItem(at: encryptedDestinationURL)
        }

        // Open the destination under SQLCipher first, then pull plaintext in via
        // sqlcipher_export(main, plaintext). Detaching the *source* avoids the
        // "database encrypted is locked" failure seen when detaching the export target.
        let encQueue = try DatabaseQueue(
            path: encryptedDestinationURL.path,
            configuration: TodoDatabase.encryptedConfiguration(passphrase: dataKey)
        )
        try encQueue.write { db in
            try db.execute(
                sql: "ATTACH DATABASE ? AS plaintext KEY ''",
                arguments: [plaintextURL.path]
            )
            // finalize via execute (not a lingering cursor)
            try db.execute(sql: "SELECT sqlcipher_export('main', 'plaintext')")
            // DETACH after sqlcipher_export often fails with "database is locked" under
            // GRDB's serialized connection; closing the queue releases the attach instead.
        }
        try encQueue.close()

        let encQueue2 = try DatabaseQueue(
            path: encryptedDestinationURL.path,
            configuration: TodoDatabase.encryptedConfiguration(passphrase: dataKey)
        )
        let after = try encQueue2.read { try countRows(in: $0) }
        guard before == after else {
            try? FileManager.default.removeItem(at: encryptedDestinationURL)
            throw AkashicMigrationError.rowCountMismatch(expected: before, actual: after)
        }
        // Apply any pending GRDB migrations on the encrypted copy (usually no-op if source was current).
        try TodoDatabase.migrator.migrate(encQueue2)
        try encQueue2.write { db in
            try SQLiteDiskBundle.requireTruncatingWalCheckpointIfWAL(db)
        }
        try encQueue2.close()

        try SetupMigrationJournal.save(
            SetupMigrationJournalPayload(
                version: SetupMigrationJournalPayload.currentVersion,
                stage: .exported,
                tempEncryptedFileName: encryptedDestinationURL.lastPathComponent,
                plaintextBackupFileName: nil
            )
        )
    }

    /// Backs up plaintext, replaces live DB with encrypted file atomically. Plaintext becomes `akashic.sqlite.plaintext-backup-<timestamp>`.
    public static func atomicSwapPlaintextForEncrypted(
        livePlaintextURL: URL,
        encryptedTempURL: URL,
        backupDirectory: URL
    ) throws -> URL {
        if let err = AkashicPlaintextMigrationTestingHooks.atomicSwapError {
            throw err
        }
        let ts = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupName = "akashic.sqlite.plaintext-backup-\(ts)"
        let backupURL = backupDirectory.appendingPathComponent(backupName)

        guard FileManager.default.fileExists(atPath: encryptedTempURL.path) else {
            throw AkashicMigrationError.missingTempEncrypted
        }

        // Ensure committed WAL data is in the main file before we move the bundle off-disk.
        try SQLiteDiskBundle.checkpointWALAndClosePlainDatabase(at: livePlaintextURL)

        guard let journal = try SetupMigrationJournal.load() else {
            throw AkashicMigrationError.missingMigrationJournal
        }
        guard journal.stage == .exported, journal.tempEncryptedFileName == encryptedTempURL.lastPathComponent else {
            throw AkashicMigrationError.missingMigrationJournal
        }

        try SQLiteDiskBundle.moveBundle(from: livePlaintextURL, to: backupURL)

        var journalSwapped = SetupMigrationJournalPayload(
            version: SetupMigrationJournalPayload.currentVersion,
            stage: .swapped,
            tempEncryptedFileName: encryptedTempURL.lastPathComponent,
            plaintextBackupFileName: backupURL.lastPathComponent
        )
        do {
            try SetupMigrationJournal.save(journalSwapped)
        } catch {
            do {
                try SQLiteDiskBundle.moveBundle(from: backupURL, to: livePlaintextURL)
            } catch let restoreError {
                throw AkashicMigrationError.swapAndRestoreFailed(
                    backupPath: backupURL.path,
                    swapDetail: String(describing: error),
                    restoreDetail: restoreError.localizedDescription
                )
            }
            throw error
        }

        do {
            try SQLiteDiskBundle.moveBundle(from: encryptedTempURL, to: livePlaintextURL)
        } catch {
            do {
                try SQLiteDiskBundle.moveBundle(from: backupURL, to: livePlaintextURL)
            } catch let restoreError {
                throw AkashicMigrationError.swapAndRestoreFailed(
                    backupPath: backupURL.path,
                    swapDetail: String(describing: error),
                    restoreDetail: restoreError.localizedDescription
                )
            }
            try SetupMigrationJournal.save(
                SetupMigrationJournalPayload(
                    version: SetupMigrationJournalPayload.currentVersion,
                    stage: .exported,
                    tempEncryptedFileName: encryptedTempURL.lastPathComponent,
                    plaintextBackupFileName: nil
                )
            )
            throw error
        }

        try SetupMigrationJournal.clear()
        return backupURL
    }
}

public enum AkashicMigrationError: Error, Equatable, Sendable {
    case rowCountMismatch(expected: AkashicPlaintextMigration.TableCounts, actual: AkashicPlaintextMigration.TableCounts)
    case missingTempEncrypted
    case missingMigrationJournal
    case swapAndRestoreFailed(backupPath: String, swapDetail: String, restoreDetail: String)
}
