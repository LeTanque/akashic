import AkashicCore
import Foundation
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
        AkashicPlaintextMigrationTestingHooks.atomicSwapError = nil
        AkashicPlaintextMigrationTestingHooks.exportPlaintextFailure = nil
        TodoDatabaseTestingHooks.createEncryptedEmptyFailure = nil
        TodoDatabaseTestingHooks.openEncryptedFailure = nil
    }

    private func makeVault() -> AkashicVaultController {
        AkashicVaultController(apiService: AkashicAPIService())
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

    /// Seed `akashic.sqlite` with a plain (non-SQLCipher) database file.
    private func installPlaintextDatabaseFixture() throws {
        let url = try dbURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        _ = try TodoDatabase.openPlain(at: url)
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: url))
    }

    private func waitUntil(
        timeout: TimeInterval = 15,
        pollMs: UInt64 = 20,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: pollMs * 1_000_000)
        }
        XCTFail("Condition not met before timeout (\(timeout)s)")
    }

    func testWrongTOTPThenRetrySucceeds() async throws {
        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()
        let otpauth = vault.setupOtpauthURI

        vault.setupTOTPCode = "000000"
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil { vault.setupError != nil }

        XCTAssertEqual(vault.setupError, "Invalid authenticator code.")
        XCTAssertEqual(vault.setupOtpauthURI, otpauth)
        XCTAssertFalse(vault.isCompletingFirstRun)

        vault.setupTOTPCode = good
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 30) { vault.presentation == .ready }

        XCTAssertNil(vault.setupError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try securityURL().path))
    }

    func testMigrationExportFailureLeavesPlaintextAndAllowsRetry() async throws {
        try installPlaintextDatabaseFixture()

        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        AkashicPlaintextMigrationTestingHooks.exportPlaintextFailure = NSError(
            domain: "TestMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: "simulated export"]
        )
        vault.setupTOTPCode = good
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 25) { vault.setupError != nil }

        XCTAssertTrue(vault.setupError?.contains("Could not encrypt or replace") == true)
        XCTAssertNotEqual(vault.setupError, "Invalid authenticator code.")
        let db = try dbURL()
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: db))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))

        AkashicPlaintextMigrationTestingHooks.exportPlaintextFailure = nil
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.presentation == .ready }

        XCTAssertFalse(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: db))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try securityURL().path))
    }

    func testMetadataSaveFailureAfterMigrationRollsBackAndRetries() async throws {
        try installPlaintextDatabaseFixture()

        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        LocalSecurityMetadataStoreTestingHooks.saveFailure = NSError(
            domain: "TestMeta", code: 2, userInfo: [NSLocalizedDescriptionKey: "simulated save"]
        )
        vault.setupTOTPCode = good
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.setupError != nil }

        XCTAssertTrue(vault.setupError?.contains("akashic-security.json") == true)
        let db = try dbURL()
        XCTAssertTrue(try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: db))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))

        LocalSecurityMetadataStoreTestingHooks.saveFailure = nil
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.presentation == .ready }

        XCTAssertTrue(FileManager.default.fileExists(atPath: try securityURL().path))
    }

    func testOpenDBFailureAfterSaveRollsBackFreshDBAndRetries() async throws {
        let vault = makeVault()
        try seedPendingSetup(vault: vault)
        let good = try vault.testingCurrentSetupTOTPCode()

        TodoDatabaseTestingHooks.openEncryptedFailure = NSError(
            domain: "TestOpen", code: 3, userInfo: [NSLocalizedDescriptionKey: "simulated open"]
        )
        vault.setupTOTPCode = good
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.setupError != nil }

        XCTAssertTrue(vault.setupError?.contains("Could not open the encrypted database") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try dbURL().path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: try securityURL().path))

        TodoDatabaseTestingHooks.openEncryptedFailure = nil
        Task { await vault.completeFirstRunAfterTOTP() }
        await waitUntil(timeout: 45) { vault.presentation == .ready }

        XCTAssertTrue(FileManager.default.fileExists(atPath: try securityURL().path))
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
}
