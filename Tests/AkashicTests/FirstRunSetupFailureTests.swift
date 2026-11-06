import AkashicCore
import Foundation
import GRDB
import XCTest
@testable import Akashic

@MainActor
final class FirstRunSetupFailureTests: XCTestCase {
    private var savedDataDir: String?
    private var tempRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        savedDataDir = ProcessInfo.processInfo.environment[AkashicPaths.dataDirectoryEnvironmentKey]
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-first-run-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        setenv(AkashicPaths.dataDirectoryEnvironmentKey, tempRoot.path, 1)
        clearTestHooks()
    }

    override func tearDown() async throws {
        if let savedDataDir {
            setenv(AkashicPaths.dataDirectoryEnvironmentKey, savedDataDir, 1)
        } else {
            unsetenv(AkashicPaths.dataDirectoryEnvironmentKey)
        }
        savedDataDir = nil
        clearTestHooks()
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

    /// Plain DB with WAL journal (real sidecar files on disk).
    private func installWALPlaintextDatabaseFixture(withPendingInsert: Bool) throws -> Int {
        let url = try dbURL()
        try SQLiteDiskBundle.removeAllIfPresent(main: url)

        var config = Configuration()
        config.label = "AkashicWalTestPlain"
        let queue = try DatabaseQueue(path: url.path, configuration: config)
        try queue.write { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        try TodoDatabase.migrator.migrate(queue)

        var count = 0
        if withPendingInsert {
            try queue.write { db in
                let ctx = try InstallationContext.loadOrCreate(in: db)
                let todo = ctx.freshTodo(title: "wal row", description: "pending WAL", priority: .medium)
                try todo.insert(db)
            }
            count = 1
        }
        try queue.close()
        XCTAssertTrue(FileManager.default.fileExists(atPath: try walURL().path))
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: url))
        return count
    }

    private func countPlainTodos() throws -> Int {
        let url = try dbURL()
        let q = try TodoDatabase.openPlain(at: url)
        defer { try? q.close() }
        return try q.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM todos WHERE deleted_at IS NULL") ?? 0
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

        let backup = URL(fileURLWithPath: "/tmp/vault/akashic.sqlite.plaintext-backup-ts", isDirectory: false)
        XCTAssertEqual(SQLiteDiskBundle.walURL(main: backup).path, backup.path + "-wal")
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

        let primary = try DatabaseQueue(path: url.path)
        try primary.write { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }

        let checkpointDone = expectation(description: "checkpoint")
        var checkpointError: Error?
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let other = try DatabaseQueue(path: url.path)
                try other.write { db in
                    try SQLiteDiskBundle.requireTruncatingWalCheckpointIfWAL(db)
                }
                try other.close()
            } catch {
                checkpointError = error
            }
            checkpointDone.fulfill()
        }

        try primary.write { db in
            try db.execute(sql: "BEGIN IMMEDIATE")
            wait(for: [checkpointDone], timeout: 5)
            try db.execute(sql: "ROLLBACK")
        }
        try primary.close()

        XCTAssertEqual(checkpointError as? AkashicSQLiteBundleError, .walCheckpointBusy)
    }

    /// DELETE journal: `wal_checkpoint` returns `(0,-1,-1)` — must not be treated as incomplete.
    func testNonWalJournalModeCheckpointIsNoOp() throws {
        let url = try dbURL()
        try SQLiteDiskBundle.removeAllIfPresent(main: url)
        let q = try DatabaseQueue(path: url.path)
        try q.write { db in
            try db.execute(sql: "PRAGMA journal_mode = DELETE")
        }
        try q.write { db in
            try SQLiteDiskBundle.requireTruncatingWalCheckpointIfWAL(db)
        }
        try q.close()
    }

    // MARK: - Setup flow

    func testWrongTOTPKeepsIncompleteAndAPILocked() async throws {
        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let otpauth = vault.setupOtpauthURI
        let recovery = vault.setupRecoveryDisplay

        vault.setupTOTPCode = "000000"
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil { vault.setupError != nil }

        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertEqual(vault.setupError, "Invalid authenticator code.")
        XCTAssertEqual(vault.setupOtpauthURI, otpauth)
        XCTAssertEqual(vault.setupRecoveryDisplay, recovery)
        XCTAssertTrue(vault.testingIsAPILocked)
        XCTAssertFalse(vault.isCompletingFirstRun)
    }

    func testMigrationExportFailurePreservesWALRowsAndKeepsSecrets() async throws {
        _ = try installWALPlaintextDatabaseFixture(withPendingInsert: true)
        XCTAssertEqual(try countPlainTodos(), 1)

        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()
        let otpauth = vault.setupOtpauthURI

        AkashicPlaintextMigrationTestingHooks.exportPlaintextFailure = NSError(
            domain: "TestMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: "simulated export"]
        )
        vault.setupTOTPCode = good
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 25) { vault.setupError != nil }

        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertTrue(vault.setupError?.contains("Could not encrypt or replace") == true)
        XCTAssertNotEqual(vault.setupError, "Invalid authenticator code.")
        XCTAssertEqual(vault.setupOtpauthURI, otpauth)
        XCTAssertTrue(vault.testingIsAPILocked)

        XCTAssertEqual(try countPlainTodos(), 1)
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: try dbURL()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))
    }

    func testOpenFailOnceAfterMigrationRollsBackThenSucceeds() async throws {
        try installPlaintextDatabaseFixture()
        XCTAssertEqual(try countPlainTodos(), 0)

        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        TodoDatabaseTestingHooks.openEncryptedFailOnce = NSError(
            domain: "TestOpenOnce", code: 9, userInfo: [NSLocalizedDescriptionKey: "fail once"]
        )
        vault.setupTOTPCode = good
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.setupError != nil }

        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertTrue(vault.setupError?.contains("Could not open the encrypted database") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: try dbURL()))
        XCTAssertEqual(try countPlainTodos(), 0)

        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.presentation == .ready }

        XCTAssertNil(vault.setupError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try securityURL().path))
        XCTAssertFalse(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: try dbURL()))
    }

    func testMetadataSaveFailureAfterMigrationRestoresPlaintext() async throws {
        try installPlaintextDatabaseFixture()
        XCTAssertEqual(try countPlainTodos(), 0)

        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        LocalSecurityMetadataStoreTestingHooks.saveFailure = NSError(
            domain: "TestMeta", code: 2, userInfo: [NSLocalizedDescriptionKey: "simulated save"]
        )
        vault.setupTOTPCode = good
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.setupError != nil }

        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertTrue(vault.setupError?.contains("akashic-security.json") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: try dbURL()))
        XCTAssertEqual(try countPlainTodos(), 0)

        LocalSecurityMetadataStoreTestingHooks.saveFailure = nil
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.presentation == .ready }

        XCTAssertTrue(FileManager.default.fileExists(atPath: try securityURL().path))
    }

    func testDuplicateFinishIgnoredWhileSavingMetadata() async throws {
        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        LocalSecurityMetadataStoreTestingHooks.saveDelayNanoseconds = 500_000_000
        let startCount = LocalSecurityMetadataStoreTestingHooks.saveEntryCount

        vault.setupTOTPCode = good
        Task { await vault.completeFirstRunAfterTOTP() }
        try await Task.sleep(nanoseconds: 50_000_000)
        await vault.completeFirstRunAfterTOTP()

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

        let vault = makeVault()
        try seedPendingSetup(vault: vault)

        TodoDatabaseTestingHooks.openEncryptedFailOnce = NSError(
            domain: "TestOpenOnce", code: 9, userInfo: [NSLocalizedDescriptionKey: "fail once"]
        )
        // Fail mid-bundle restore after plaintext backup includes `-wal` (first move = main, second = wal).
        SQLiteDiskBundleTestingHooks.moveBundleFailAfterNSuccessfulMoves = 2
        vault.setupTOTPCode = try vault.testingCurrentSetupTOTPCode()
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.setupRequiresManualRecoveryReason != nil }

        XCTAssertEqual(vault.presentation, .firstRun)
        XCTAssertNotNil(vault.setupRequiresManualRecoveryReason)
        XCTAssertTrue(vault.setupError?.contains("could not roll back safely") == true)
        XCTAssertTrue(vault.testingIsAPILocked)
        SQLiteDiskBundleTestingHooks.moveBundleFailAfterNSuccessfulMoves = nil

        vault.advanceFirstRunToCodes()
        XCTAssertNotNil(vault.setupRequiresManualRecoveryReason)

        vault.goBackFromFirstRunConfirmToCodes()
        XCTAssertNotNil(vault.setupRequiresManualRecoveryReason)

        XCTAssertNotNil(try SetupManualRecoveryStore.loadReason())
    }

    func testManualRecoveryPersistsAcrossNewController() async throws {
        let vault = makeVault()
        vault.testingArmManualRecoveryForTests("test disk hazard")

        let vault2 = makeVault()
        vault2.testingRefreshManualRecoveryFromDisk()

        XCTAssertEqual(vault2.setupRequiresManualRecoveryReason, "test disk hazard")
        XCTAssertEqual(vault2.setupError, "test disk hazard")
    }

    func testCreateEmptyDBFailureDoesNotWriteArtifacts() async throws {
        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        TodoDatabaseTestingHooks.createEncryptedEmptyFailure = NSError(
            domain: "TestCreate", code: 4, userInfo: [NSLocalizedDescriptionKey: "simulated create"]
        )
        vault.setupTOTPCode = good
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil { vault.setupError != nil }

        XCTAssertTrue(vault.setupError?.contains("Could not create the encrypted database") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try dbURL().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))
    }

    // MARK: - Helpers (non-WAL)

    /// Seed `akashic.sqlite` with a plain (non-SQLCipher) database file.
    private func installPlaintextDatabaseFixture() throws {
        let url = try dbURL()
        try SQLiteDiskBundle.removeAllIfPresent(main: url)
        _ = try TodoDatabase.openPlain(at: url)
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: url))
    }
}
