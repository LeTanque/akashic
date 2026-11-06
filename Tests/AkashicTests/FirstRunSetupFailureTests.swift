import AkashicCore
import Foundation
import GRDB
import SQLite3
import XCTest
@testable import Akashic

@MainActor
final class FirstRunSetupFailureTests: XCTestCase {
    private static let apiPortEnvKey = "AKASHIC_API_PORT"
    private var savedApiPort: String?
    private var savedDataDir: String?
    private var tempRoot: URL!
    /// Kept open so SQLite does not run a final checkpoint that deletes `-wal` before migration/export runs.
    private var walFixtureWriterQueue: DatabaseQueue?

    override func setUp() async throws {
        try await super.setUp()
        savedDataDir = ProcessInfo.processInfo.environment[AkashicPaths.dataDirectoryEnvironmentKey]
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-first-run-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        setenv(AkashicPaths.dataDirectoryEnvironmentKey, tempRoot.path, 1)
        savedApiPort = ProcessInfo.processInfo.environment[Self.apiPortEnvKey]
        let ephemeralPort = 23000 + (ProcessInfo.processInfo.processIdentifier % 20000)
        setenv(Self.apiPortEnvKey, String(ephemeralPort), 1)
        clearTestHooks()
        try releaseWalFixtureConnection()
    }

    override func tearDown() async throws {
        if let savedDataDir {
            setenv(AkashicPaths.dataDirectoryEnvironmentKey, savedDataDir, 1)
        } else {
            unsetenv(AkashicPaths.dataDirectoryEnvironmentKey)
        }
        savedDataDir = nil
        if let savedApiPort {
            setenv(Self.apiPortEnvKey, savedApiPort, 1)
        } else {
            unsetenv(Self.apiPortEnvKey)
        }
        savedApiPort = nil
        clearTestHooks()
        try? releaseWalFixtureConnection()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try await super.tearDown()
    }

    private func clearTestHooks() {
        LocalSecurityMetadataStoreTestingHooks.saveFailure = nil
        LocalSecurityMetadataStoreTestingHooks.saveDelayNanoseconds = 0
        LocalSecurityMetadataStoreTestingHooks.saveEntryCount = 0
        AkashicPlaintextMigrationTestingHooks.atomicSwapError = nil
        AkashicPlaintextMigrationTestingHooks.exportPlaintextFailure = nil
        TodoDatabaseTestingHooks.createEncryptedEmptyFailure = nil
        TodoDatabaseTestingHooks.openEncryptedFailure = nil
        TodoDatabaseTestingHooks.openEncryptedFailOnce = nil
        SQLiteDiskBundleTestingHooks.moveBundleFailAfterNSuccessfulMoves = nil
        SQLiteDiskBundleTestingHooks.unwindFailure = nil
        SetupMigrationJournalTestingHooks.saveFailure = nil
        SetupMigrationJournalTestingHooks.saveInvocationCount = 0
        SetupMigrationJournalTestingHooks.failOnSaveInvocation = nil
        SetupManualRecoveryStoreTestingHooks.primarySaveFailure = nil
        SQLiteDiskBundleTestingHooks.unwindAttemptCount = 0
        try? SetupManualRecoveryUserDefaultsStore.clear()
    }

    private func releaseWalFixtureConnection() throws {
        if let q = walFixtureWriterQueue {
            try q.close()
            walFixtureWriterQueue = nil
        }
    }

    private func startVaultForFirstRun(_ vault: AkashicVaultController) async {
        vault.start()
        await waitUntil { vault.presentation == .firstRun }
    }

    private func makeVault() -> AkashicVaultController {
        let api = AkashicAPIService()
        XCTAssertTrue(api.isLocked)
        return AkashicVaultController(apiService: api)
    }

    private func seedPendingSetup(vault: AkashicVaultController) throws {
        vault.setupUsername = "testuser"
        vault.setupPassword = "password12"
        vault.setupConfirmPassword = "password12"
        vault.advanceFirstRunToCodes()
        XCTAssertNil(vault.setupError)
        vault.advanceFirstRunToConfirm()
    }

    private func securityURL() throws -> URL {
        try AkashicPaths.securityMetadataURL()
    }

    private func dbURL() throws -> URL {
        try AkashicPaths.databaseURL()
    }

    private func walURL() throws -> URL {
        let u = try dbURL()
        return URL(fileURLWithPath: u.path + "-wal", isDirectory: false)
    }

    /// Diagnostics: `journal_mode` via read; raw **`PRAGMA wal_checkpoint(TRUNCATE)`** triple outside a write txn.
    private func walCheckpointDiagnostics(queue: DatabaseQueue, label: String) throws -> String {
        let jm = try queue.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "?" }
        let triple = try queue.writeWithoutTransaction { db -> String in
            if let row = try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(TRUNCATE)") {
                let busy: Int64 = row["busy"]
                let log: Int64 = row["log"]
                let checkpointed: Int64 = row["checkpointed"]
                return "wal_checkpoint busy=\(busy) log=\(log) checkpointed=\(checkpointed)"
            }
            return "wal_checkpoint returned no row"
        }
        return "\(label): journal_mode=\(jm) \(triple)"
    }

    /// Plain DB with WAL journal. Leaves **`walFixtureWriterQueue`** open with a committed writer so `-wal`
    /// remains on disk (closing the last connection can checkpoint and remove `-wal`). Call
    /// **`releaseWalFixtureConnection()`** before code that must open the DB exclusively (migration).
    private func installWALPlaintextDatabaseFixture(
        withPendingInsert: Bool,
        title: String = "wal row",
        description: String = "pending WAL"
    ) throws -> Int {
        try releaseWalFixtureConnection()
        let url = try dbURL()
        try SQLiteDiskBundle.removeAllIfPresent(main: url)

        var setupConfig = Configuration()
        setupConfig.label = "AkashicWalTestPlainSetup"
        let setupQueue = try DatabaseQueue(path: url.path, configuration: setupConfig)
        try setupQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
        }
        try TodoDatabase.migrator.migrate(setupQueue)
        if withPendingInsert {
            try setupQueue.write { db in
                let ctx = try InstallationContext.loadOrCreate(in: db)
                let todo = ctx.freshTodo(title: title, description: description, priority: .medium)
                try todo.insert(db)
            }
        } else {
            // Migration alone may not create a `-wal` file; force one small committed write.
            try setupQueue.write { db in
                _ = try InstallationContext.loadOrCreate(in: db)
            }
        }
        try setupQueue.close()

        // Second connection: distinctive committed row lives only in WAL until checkpoint (export path).
        var writerConfig = Configuration()
        writerConfig.label = "AkashicWalTestPlainWriter"
        let writer = try DatabaseQueue(path: url.path, configuration: writerConfig)
        try writer.writeWithoutTransaction { db in
            // New pools can still use DELETE until explicitly switched to WAL.
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
        }
        if withPendingInsert {
            try writer.write { db in
                let ctx = try InstallationContext.loadOrCreate(in: db)
                let todo = ctx.freshTodo(
                    title: "WAL-only \(UUID().uuidString.prefix(8))",
                    description: "distinctive WAL-only row",
                    priority: .low
                )
                try todo.insert(db)
            }
        } else {
            try writer.write { db in
                let ctx = try InstallationContext.loadOrCreate(in: db)
                let todo = ctx.freshTodo(
                    title: "WAL-only-empty-fixture \(UUID().uuidString.prefix(8))",
                    description: "distinctive WAL-only row",
                    priority: .low
                )
                try todo.insert(db)
            }
        }
        walFixtureWriterQueue = writer

        let modeDiag = try walCheckpointDiagnostics(queue: writer, label: "wal-fixture-writer")
        let jm = try writer.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? "?" }
        XCTAssertEqual(
            jm.lowercased(),
            "wal",
            "Writer must be in WAL for WAL export tests. \(modeDiag)"
        )
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: url))
        XCTAssertEqual(try countPlainTodos(), withPendingInsert ? 2 : 1)
        return withPendingInsert ? 2 : 1
    }

    /// Plain DB using DELETE journal mode (no `-wal`); still validates full-row preservation on migration failure.
    private func installDeleteJournalPlaintextFixture(title: String, description: String) throws {
        try releaseWalFixtureConnection()
        let url = try dbURL()
        try SQLiteDiskBundle.removeAllIfPresent(main: url)

        let queue = try DatabaseQueue(path: url.path)
        try queue.write { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
        }
        try TodoDatabase.migrator.migrate(queue)
        try queue.write { db in
            let ctx = try InstallationContext.loadOrCreate(in: db)
            let todo = ctx.freshTodo(title: title, description: description, priority: .medium)
            try todo.insert(db)
        }
        try queue.close()
        XCTAssertFalse(FileManager.default.fileExists(atPath: try walURL().path))
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: url))
    }

    private func countPlainTodos() throws -> Int {
        let url = try dbURL()
        let q = try TodoDatabase.openPlain(at: url)
        defer { try? q.close() }
        return try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM todos WHERE deleted_at IS NULL") ?? 0
        }
    }

    private func plainActiveTodoTitles() throws -> [String] {
        let url = try dbURL()
        let q = try TodoDatabase.openPlain(at: url)
        defer { try? q.close() }
        return try q.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM todos WHERE deleted_at IS NULL ORDER BY title")
        }
    }

    private func firstPlainActiveTodoTitleAndDescription() throws -> (String, String) {
        let url = try dbURL()
        let q = try TodoDatabase.openPlain(at: url)
        defer { try? q.close() }
        return try q.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT title, description FROM todos WHERE deleted_at IS NULL ORDER BY title LIMIT 1"
            )
            guard let row else {
                struct MissingRow: Error {}
                throw MissingRow()
            }
            return (row["title"], row["description"])
        }
    }

    private func plainTodoTitleAndDescription(whereTitleEquals title: String) throws -> (String, String) {
        let url = try dbURL()
        let q = try TodoDatabase.openPlain(at: url)
        defer { try? q.close() }
        return try q.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT title, description FROM todos WHERE deleted_at IS NULL AND title = ?",
                arguments: [title]
            )
            guard let row else {
                struct MissingRow: Error {}
                throw MissingRow()
            }
            return (row["title"], row["description"])
        }
    }

    private func plainTodoTitleAndDescription(whereTitleHasPrefix prefix: String) throws -> (String, String) {
        let url = try dbURL()
        let q = try TodoDatabase.openPlain(at: url)
        defer { try? q.close() }
        return try q.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT title, description FROM todos WHERE deleted_at IS NULL AND title LIKE ? ORDER BY title LIMIT 1",
                arguments: ["\(prefix)%"]
            )
            guard let row else {
                struct MissingRow: Error {}
                throw MissingRow()
            }
            return (row["title"], row["description"])
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 15,
        pollMs: UInt64 = 20,
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: pollMs * 1_000_000)
        }
        XCTFail("Condition not met before timeout (\(timeout)s)", file: file, line: line)
    }

    // MARK: - Path / bundle semantics

    func testSQLiteSidecarPathsAppendSuffixNotExtensionSwap() throws {
        let base = URL(fileURLWithPath: "/tmp/vault/akashic.sqlite", isDirectory: false)
        XCTAssertEqual(SQLiteDiskBundle.journalURL(main: base).path, base.path + "-journal")
        XCTAssertEqual(SQLiteDiskBundle.walURL(main: base).path, base.path + "-wal")
        XCTAssertEqual(SQLiteDiskBundle.shmURL(main: base).path, base.path + "-shm")

        let backup = URL(
            fileURLWithPath: "/tmp/vault/\(AkashicPlaintextBackupNames.plaintextBackupFilename(for: Date(timeIntervalSince1970: 0)))",
            isDirectory: false
        )
        XCTAssertEqual(SQLiteDiskBundle.walURL(main: backup).path, backup.path + "-wal")
    }

    func testPlaintextBackupNamingMatchesMigration() {
        let name = AkashicPlaintextBackupNames.plaintextBackupFilename(for: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(name.hasPrefix(AkashicPlaintextBackupNames.prefix))
        XCTAssertFalse(name.hasSuffix(".sqlite"), "Real migration backup has no .sqlite extension")
        XCTAssertTrue(AkashicPlaintextBackupNames.isPlaintextBackupFilename(name))
    }

    func testMoveBundlePartialFailureRestoresSource() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bundle-move-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let srcMain = dir.appendingPathComponent("src.sqlite")
        let dstMain = dir.appendingPathComponent("dst.sqlite")
        try Data("sqlite".utf8).write(to: srcMain)
        let srcWal = SQLiteDiskBundle.walURL(main: srcMain)
        try Data("wal".utf8).write(to: srcWal)

        SQLiteDiskBundleTestingHooks.moveBundleFailAfterNSuccessfulMoves = 2
        XCTAssertThrowsError(try SQLiteDiskBundle.moveBundle(from: srcMain, to: dstMain)) { err in
            XCTAssertEqual(err as? AkashicSQLiteBundleError, .simulatedMoveFailure)
        }
        SQLiteDiskBundleTestingHooks.moveBundleFailAfterNSuccessfulMoves = nil

        XCTAssertTrue(FileManager.default.fileExists(atPath: srcMain.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: srcWal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dstMain.path))
    }

    func testWalCheckpointBusyWithConcurrentWriterLock() throws {
        let url = try dbURL()
        try SQLiteDiskBundle.removeAllIfPresent(main: url)

        let readerReady = DispatchSemaphore(value: 0)
        let checkpointDone = DispatchSemaphore(value: 0)
        let readerMayExit = DispatchSemaphore(value: 0)
        var readerSetupError: String?
        let readerErrLock = NSLock()

        let readerThread = Thread {
            var db: OpaquePointer?
            let openRc = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
            guard openRc == SQLITE_OK, let conn = db else {
                readerErrLock.lock()
                readerSetupError = "reader open failed \(openRc)"
                readerErrLock.unlock()
                readerReady.signal()
                return
            }
            defer { sqlite3_close(conn) }
            do {
                try Self.sqlite3Exec(conn, "PRAGMA journal_mode = WAL")
                try Self.sqlite3Exec(conn, "PRAGMA wal_autocheckpoint = 0")
                try Self.sqlite3Exec(
                    conn,
                    "CREATE TABLE IF NOT EXISTS wal_checkpoint_busy_probe (id INTEGER PRIMARY KEY)"
                )
                try Self.sqlite3Exec(conn, "INSERT INTO wal_checkpoint_busy_probe (id) VALUES (1)")
                // Read transaction blocks truncating checkpoint while frames remain in WAL.
                try Self.sqlite3Exec(conn, "BEGIN DEFERRED")
                var stmt: OpaquePointer?
                defer { sqlite3_finalize(stmt) }
                guard sqlite3_prepare_v2(
                    conn,
                    "SELECT id FROM wal_checkpoint_busy_probe",
                    -1,
                    &stmt,
                    nil
                ) == SQLITE_OK else {
                    throw NSError(domain: "BusyTest", code: 1)
                }
                guard sqlite3_step(stmt) == SQLITE_ROW else {
                    throw NSError(domain: "BusyTest", code: 2)
                }
            } catch {
                readerErrLock.lock()
                readerSetupError = String(describing: error)
                readerErrLock.unlock()
                readerReady.signal()
                return
            }
            readerReady.signal()
            checkpointDone.wait()
            try? Self.sqlite3Exec(conn, "ROLLBACK")
            readerMayExit.signal()
        }
        readerThread.start()

        readerReady.wait()
        readerErrLock.lock()
        let rErr = readerSetupError
        readerErrLock.unlock()
        if let rErr {
            XCTFail(rErr)
            return
        }

        var checkpointError: Error?
        let grdb = try DatabaseQueue(path: url.path)
        let diagBefore = try walCheckpointDiagnostics(queue: grdb, label: "busy-test-grdb")
        try grdb.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA wal_autocheckpoint = 0")
            // So a contended checkpoint blocks up to 30s (then returns busy / SQLITE_BUSY) instead of failing instantly.
            try db.execute(sql: "PRAGMA busy_timeout = 30000")
        }
        try grdb.write { db in
            try db.execute(sql: "INSERT INTO wal_checkpoint_busy_probe (id) VALUES (2)")
        }
        do {
            try grdb.writeWithoutTransaction { db in
                try SQLiteDiskBundle.requireTruncatingWalCheckpointIfWAL(db)
            }
            checkpointError = nil
        } catch {
            checkpointError = error
        }
        // Unblock reader as soon as the checkpoint attempt returns (success or failure).
        checkpointDone.signal()

        if let ck = checkpointError as? AkashicSQLiteBundleError, ck == .walCheckpointBusy {
            XCTAssertEqual(
                readerMayExit.wait(timeout: .now() + 30),
                .success,
                "reader thread did not finish after busy checkpoint. \(diagBefore)"
            )
            // After reader releases its snapshot, truncating checkpoint must succeed (production path).
            try grdb.writeWithoutTransaction { db in
                try SQLiteDiskBundle.requireTruncatingWalCheckpointIfWAL(db)
            }
            try grdb.close()
            return
        }

        XCTAssertEqual(
            readerMayExit.wait(timeout: .now() + 30),
            .success,
            "reader thread did not finish after checkpoint. \(diagBefore)"
        )
        let diagAfter = try walCheckpointDiagnostics(queue: grdb, label: "busy-test-after-failure")
        try grdb.close()

        if checkpointError == nil {
            XCTFail("Expected .walCheckpointBusy; checkpoint succeeded. \(diagBefore)")
        } else {
            XCTFail(
                "Expected .walCheckpointBusy, got \(String(describing: checkpointError)). \(diagBefore) \(diagAfter)"
            )
        }
    }

    private nonisolated static func sqlite3Exec(_ db: OpaquePointer?, _ sql: String) throws {
        var errMsg: UnsafeMutablePointer<Int8>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        guard rc == SQLITE_OK else {
            let message = errMsg.map { String(cString: $0) } ?? "sqlite3_exec failed (\(rc))"
            sqlite3_free(errMsg)
            throw NSError(domain: "SQLite3Test", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    /// DELETE journal: `wal_checkpoint` returns `(0,-1,-1)` — must not be treated as incomplete.
    func testNonWalJournalModeCheckpointIsNoOp() throws {
        let url = try dbURL()
        try SQLiteDiskBundle.removeAllIfPresent(main: url)
        let q = try DatabaseQueue(path: url.path)
        try q.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
        }
        try q.writeWithoutTransaction { db in
            try SQLiteDiskBundle.requireTruncatingWalCheckpointIfWAL(db)
        }
        try q.close()
    }

    // MARK: - Setup flow

    func testWrongTOTPKeepsIncompleteAndAPILocked() async throws {
        let vault = makeVault()
        await startVaultForFirstRun(vault)
        try seedPendingSetup(vault: vault)
        let otpauth = vault.setupOtpauthURI
        let recovery = vault.setupRecoveryDisplay

        vault.setupTOTPCode = "000000"
        await vault.completeFirstRunAfterTOTP()
        await waitUntil { vault.setupError != nil }

        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertEqual(vault.setupError, "Invalid authenticator code.")
        XCTAssertEqual(vault.setupOtpauthURI, otpauth)
        XCTAssertEqual(vault.setupRecoveryDisplay, recovery)
        XCTAssertTrue(vault.testingIsAPILocked)
        XCTAssertFalse(vault.isCompletingFirstRun)
    }

    func testMigrationExportFailurePreservesWALRowsAndKeepsSecrets() async throws {
        let uniqueTitle = "wal row \(UUID().uuidString.prefix(8))"
        let uniqueBody = "pending WAL body \(UUID().uuidString.prefix(8))"
        _ = try installWALPlaintextDatabaseFixture(
            withPendingInsert: true,
            title: uniqueTitle,
            description: uniqueBody
        )
        XCTAssertEqual(try countPlainTodos(), 2)
        let (savedTitle, savedBody) = try plainTodoTitleAndDescription(whereTitleEquals: uniqueTitle)
        XCTAssertEqual(savedTitle, uniqueTitle)
        XCTAssertEqual(savedBody, uniqueBody)
        let (walOnlyTitle, walOnlyDesc) = try plainTodoTitleAndDescription(whereTitleHasPrefix: "WAL-only ")
        XCTAssertTrue(walOnlyTitle.hasPrefix("WAL-only "))
        XCTAssertEqual(walOnlyDesc, "distinctive WAL-only row")

        try releaseWalFixtureConnection()

        let vault = makeVault()
        await startVaultForFirstRun(vault)
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()
        let otpauth = vault.setupOtpauthURI

        AkashicPlaintextMigrationTestingHooks.exportPlaintextFailure = NSError(
            domain: "TestMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: "simulated export"]
        )
        vault.setupTOTPCode = good
        await vault.completeFirstRunAfterTOTP()
        await waitUntil(timeout: 25) { vault.setupError != nil }

        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertTrue(vault.setupError?.contains("Could not encrypt or replace") == true)
        XCTAssertNotEqual(vault.setupError, "Invalid authenticator code.")
        XCTAssertEqual(vault.setupOtpauthURI, otpauth)
        XCTAssertTrue(vault.testingIsAPILocked)

        XCTAssertEqual(try countPlainTodos(), 2)
        let (afterTitle, afterBody) = try plainTodoTitleAndDescription(whereTitleEquals: uniqueTitle)
        XCTAssertEqual(afterTitle, uniqueTitle)
        XCTAssertEqual(afterBody, uniqueBody)
        let (afterWalTitle, afterWalDesc) = try plainTodoTitleAndDescription(whereTitleHasPrefix: "WAL-only ")
        XCTAssertTrue(afterWalTitle.hasPrefix("WAL-only "))
        XCTAssertEqual(afterWalDesc, "distinctive WAL-only row")
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: try dbURL()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))
    }

    func testOpenFailOnceAfterMigrationRollsBackThenSucceeds() async throws {
        let uniqueTitle = "delete journal row \(UUID().uuidString.prefix(8))"
        try installPlaintextDatabaseFixture(seedTodoTitle: uniqueTitle)
        XCTAssertEqual(try countPlainTodos(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try walURL().path))
        XCTAssertEqual(try plainActiveTodoTitles(), [uniqueTitle])

        let vault = makeVault()
        await startVaultForFirstRun(vault)
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        TodoDatabaseTestingHooks.openEncryptedFailOnce = NSError(
            domain: "TestOpenOnce", code: 9, userInfo: [NSLocalizedDescriptionKey: "fail once"]
        )
        vault.setupTOTPCode = good
        await vault.completeFirstRunAfterTOTP()
        await waitUntil(timeout: 45) { vault.setupError != nil }

        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertTrue(vault.setupError?.contains("Could not open the encrypted database") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: try dbURL()))
        XCTAssertEqual(try countPlainTodos(), 1)
        XCTAssertEqual(try plainActiveTodoTitles(), [uniqueTitle])

        await vault.completeFirstRunAfterTOTP()
        await waitUntil(timeout: 45) { vault.presentation == .ready }

        XCTAssertNil(vault.setupError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try securityURL().path))
        XCTAssertFalse(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: try dbURL()))
    }

    func testMetadataSaveFailureAfterMigrationRestoresPlaintext() async throws {
        let uniqueTitle = "metadata rollback \(UUID().uuidString.prefix(8))"
        try installPlaintextDatabaseFixture(seedTodoTitle: uniqueTitle)
        XCTAssertEqual(try countPlainTodos(), 1)
        XCTAssertEqual(try plainActiveTodoTitles(), [uniqueTitle])

        let vault = makeVault()
        await startVaultForFirstRun(vault)
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        LocalSecurityMetadataStoreTestingHooks.saveFailure = NSError(
            domain: "TestMeta", code: 2, userInfo: [NSLocalizedDescriptionKey: "simulated save"]
        )
        vault.setupTOTPCode = good
        await vault.completeFirstRunAfterTOTP()
        await waitUntil(timeout: 45) { vault.setupError != nil }

        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertTrue(vault.setupError?.contains("akashic-security.json") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: try dbURL()))
        XCTAssertEqual(try countPlainTodos(), 1)
        XCTAssertEqual(try plainActiveTodoTitles(), [uniqueTitle])

        LocalSecurityMetadataStoreTestingHooks.saveFailure = nil
        await vault.completeFirstRunAfterTOTP()
        await waitUntil(timeout: 45) { vault.presentation == .ready }

        XCTAssertTrue(FileManager.default.fileExists(atPath: try securityURL().path))
    }

    func testDuplicateFinishIgnoredWhileSavingMetadata() async throws {
        let vault = makeVault()
        await startVaultForFirstRun(vault)
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        LocalSecurityMetadataStoreTestingHooks.saveDelayNanoseconds = 500_000_000
        let startCount = LocalSecurityMetadataStoreTestingHooks.saveEntryCount

        vault.setupTOTPCode = good
        async let first: Void = vault.completeFirstRunAfterTOTP()
        try await Task.sleep(nanoseconds: 50_000_000)
        await vault.completeFirstRunAfterTOTP()
        await first

        await waitUntil(timeout: 30) { vault.presentation == .ready }

        XCTAssertGreaterThanOrEqual(
            LocalSecurityMetadataStoreTestingHooks.saveEntryCount,
            startCount + 1,
            "Finish path should reach metadata save at least once"
        )
        XCTAssertEqual(
            LocalSecurityMetadataStoreTestingHooks.saveEntryCount,
            startCount + 1,
            "Second finish during save should not commit metadata twice"
        )
    }

    func testRollbackFailureSurfacesManualRecoveryAndBlocksWizard() async throws {
        _ = try installWALPlaintextDatabaseFixture(withPendingInsert: false)
        try releaseWalFixtureConnection()

        let vault = makeVault()
        await startVaultForFirstRun(vault)
        try seedPendingSetup(vault: vault)

        TodoDatabaseTestingHooks.openEncryptedFailOnce = NSError(
            domain: "TestOpenOnce", code: 9, userInfo: [NSLocalizedDescriptionKey: "fail once"]
        )
        // Fail while restoring the plaintext bundle from backup (after first moved file), then fail bundle unwind.
        SQLiteDiskBundleTestingHooks.moveBundleFailAfterNSuccessfulMoves = 1
        SQLiteDiskBundleTestingHooks.unwindFailure = NSError(
            domain: "TestUnwind", code: 3, userInfo: [NSLocalizedDescriptionKey: "simulated unwind failure"]
        )
        vault.setupTOTPCode = try vault.testingCurrentSetupTOTPCode()
        await vault.completeFirstRunAfterTOTP()
        await waitUntil(timeout: 45) { vault.setupRequiresManualRecoveryReason != nil }

        XCTAssertGreaterThan(SQLiteDiskBundleTestingHooks.unwindAttemptCount, 0, "unwind path should run")
        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertNotNil(vault.setupRequiresManualRecoveryReason)
        XCTAssertTrue(vault.setupError?.contains("could not roll back safely") == true)
        XCTAssertTrue(vault.testingIsAPILocked)
        SQLiteDiskBundleTestingHooks.moveBundleFailAfterNSuccessfulMoves = nil
        SQLiteDiskBundleTestingHooks.unwindFailure = nil

        vault.advanceFirstRunToCodes()
        XCTAssertNotNil(vault.setupRequiresManualRecoveryReason)

        vault.goBackFromFirstRunConfirmToCodes()
        XCTAssertNotNil(vault.setupRequiresManualRecoveryReason)

        XCTAssertNotNil(try SetupManualRecoveryStore.loadReason())

        let vaultRelaunch = makeVault()
        vaultRelaunch.start()
        await waitUntil {
            vaultRelaunch.presentation == .firstRun && vaultRelaunch.setupRequiresManualRecoveryReason != nil
        }
        XCTAssertNotNil(vaultRelaunch.setupRequiresManualRecoveryReason)
    }

    func testManualRecoveryPersistsAcrossNewController() async throws {
        let vault = makeVault()
        vault.testingArmManualRecoveryForTests("test disk hazard")

        let vault2 = makeVault()
        vault2.start()
        await waitUntil { vault2.presentation == .firstRun }
        XCTAssertEqual(vault2.setupRequiresManualRecoveryReason, "test disk hazard")
        XCTAssertEqual(vault2.setupError, "test disk hazard")
    }

    func testCreateEmptyDBFailureDoesNotWriteArtifacts() async throws {
        let vault = makeVault()
        await startVaultForFirstRun(vault)
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        TodoDatabaseTestingHooks.createEncryptedEmptyFailure = NSError(
            domain: "TestCreate", code: 4, userInfo: [NSLocalizedDescriptionKey: "simulated create"]
        )
        vault.setupTOTPCode = good
        await vault.completeFirstRunAfterTOTP()
        await waitUntil { vault.setupError != nil }

        XCTAssertTrue(vault.setupError?.contains("Could not create the encrypted database") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try dbURL().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))
    }

    func testMigrationJournalFirstSaveFailureRollsBackTempEncryptedFile() async throws {
        try installPlaintextDatabaseFixture(seedTodoTitle: "journal fail")
        SetupMigrationJournalTestingHooks.failOnSaveInvocation = 1
        SetupMigrationJournalTestingHooks.saveFailure = NSError(
            domain: "TestJournal", code: 7, userInfo: [NSLocalizedDescriptionKey: "simulated journal write"]
        )

        let vault = makeVault()
        await startVaultForFirstRun(vault)
        try seedPendingSetup(vault: vault)
        vault.setupTOTPCode = try vault.testingCurrentSetupTOTPCode()
        await vault.completeFirstRunAfterTOTP()
        await waitUntil { vault.setupError != nil }

        XCTAssertFalse(FileManager.default.fileExists(atPath: try SetupMigrationJournal.fileURL().path))
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: try dbURL()))
    }

    func testMigrationExportFailurePreservesDeleteJournalRowContent() async throws {
        let uniqueTitle = "delete fixture \(UUID().uuidString.prefix(8))"
        let uniqueBody = "delete body \(UUID().uuidString.prefix(8))"
        try installDeleteJournalPlaintextFixture(title: uniqueTitle, description: uniqueBody)
        XCTAssertEqual(try countPlainTodos(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try walURL().path))

        let vault = makeVault()
        await startVaultForFirstRun(vault)
        try seedPendingSetup(vault: vault)
        AkashicPlaintextMigrationTestingHooks.exportPlaintextFailure = NSError(
            domain: "TestMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: "simulated export"]
        )
        vault.setupTOTPCode = try vault.testingCurrentSetupTOTPCode()
        await vault.completeFirstRunAfterTOTP()
        await waitUntil { vault.setupError != nil }

        XCTAssertEqual(try countPlainTodos(), 1)
        let (t, d) = try firstPlainActiveTodoTitleAndDescription()
        XCTAssertEqual(t, uniqueTitle)
        XCTAssertEqual(d, uniqueBody)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try walURL().path))
    }

    func testManualRecoveryMarkerFallsBackToUserDefaultsWhenDiskFails() async throws {
        SetupManualRecoveryStoreTestingHooks.primarySaveFailure = NSError(
            domain: "TestDiskFull", code: 28, userInfo: [NSLocalizedDescriptionKey: "simulated disk full"]
        )
        let vault = makeVault()
        XCTAssertNil(try SetupManualRecoveryStore.loadReason())

        vault.testingArmManualRecoveryForTests("marker via user defaults")

        let vault2 = makeVault()
        vault2.start()
        await waitUntil { vault2.presentation == .firstRun && vault2.setupRequiresManualRecoveryReason != nil }
        XCTAssertEqual(vault2.setupRequiresManualRecoveryReason, "marker via user defaults")
    }

    func testOrphanPlaintextBackupWithoutLiveDbBlocksEmptyVault() async throws {
        let folder = try AkashicPaths.applicationSupportFolder()
        let backup = folder.appendingPathComponent(
            AkashicPlaintextBackupNames.plaintextBackupFilename(for: Date(timeIntervalSince1970: 1_700_000_001))
        )
        let magic = "SQLite format 3\u{0}".data(using: .ascii)!
        try magic.write(to: backup)

        let vault = makeVault()
        vault.start()
        await waitUntil { vault.presentation == .firstRun && vault.setupRequiresManualRecoveryReason != nil }
        XCTAssertTrue(vault.setupRequiresManualRecoveryReason?.contains("plaintext database backup exists at") == true)
    }

    // MARK: - Helpers (non-WAL)

    /// Seed `akashic.sqlite` with a plain (non-SQLCipher) database file.
    private func installPlaintextDatabaseFixture(seedTodoTitle: String? = nil) throws {
        try releaseWalFixtureConnection()
        let url = try dbURL()
        try SQLiteDiskBundle.removeAllIfPresent(main: url)
        let q = try TodoDatabase.openPlain(at: url)
        if let seedTodoTitle {
            try q.write { db in
                let ctx = try InstallationContext.loadOrCreate(in: db)
                let todo = ctx.freshTodo(
                    title: seedTodoTitle,
                    description: "fixture description body",
                    priority: .medium
                )
                try todo.insert(db)
            }
        }
        try q.close()
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: url))
    }
}
