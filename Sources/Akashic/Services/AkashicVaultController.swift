import AkashicCore
import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class AkashicVaultController: ObservableObject {
    enum Presentation: Equatable {
        case loading
        case firstRun
        case unlock
        case ready
    }

    @Published private(set) var presentation: Presentation = .loading
    @Published private(set) var todoStore: TodoStore?
    @Published private(set) var noteStore: NoteStore?

    enum FirstRunStep: Equatable {
        case credentials
        case codes
        case confirm
    }

    @Published var setupUsername = ""
    @Published var setupPassword = ""
    @Published var setupConfirmPassword = ""
    @Published var setupTOTPCode = ""
    @Published var firstRunStep: FirstRunStep = .credentials
    @Published var setupOtpauthURI = ""
    @Published var setupRecoveryDisplay = ""
    @Published var setupError: String?
    @Published private(set) var isCompletingFirstRun = false
    /// Set when rollback after a failed finish cannot restore a safe on-disk state (requires manual recovery).
    @Published private(set) var setupRequiresManualRecoveryReason: String?

    private var pendingMetadata: LocalSecurityMetadata?
    private var pendingDataKey: Data?

    @Published var unlockUsername = ""
    @Published var unlockPassword = ""
    @Published var unlockTOTP = ""
    @Published var unlockRecoveryCode = ""
    @Published var unlockError: String?

    @Published var biometricUnlockEnabled: Bool {
        didSet { UserDefaults.standard.set(biometricUnlockEnabled, forKey: Self.biometricKey) }
    }

    /// Minutes; 0 disables idle auto-lock.
    @Published var autoLockIdleMinutes: Int {
        didSet {
            UserDefaults.standard.set(autoLockIdleMinutes, forKey: Self.autoLockKey)
            if presentation == .ready {
                configureAutoLockAndSleep()
            }
        }
    }

    private let apiService: AkashicAPIService
    private var idleMonitor: IdleTimeLockMonitor?
    /// Cleared in `deinit`; `nonisolated(unsafe)` so teardown can run off MainActor.
    nonisolated(unsafe) private var sleepObservers: [NSObjectProtocol] = []

    private static let biometricKey = "akashic.security.biometricUnlock"
    private static let autoLockKey = "akashic.security.autoLockIdleMinutes"

    init(apiService: AkashicAPIService) {
        self.apiService = apiService
        biometricUnlockEnabled = UserDefaults.standard.object(forKey: Self.biometricKey) as? Bool ?? false
        if let saved = UserDefaults.standard.object(forKey: Self.autoLockKey) as? Int {
            autoLockIdleMinutes = saved
        } else {
            autoLockIdleMinutes = 15
        }
        refreshManualRecoveryFromDisk()
    }

    /// Package tests: verify localhost API stays locked during failed setup.
    internal var testingIsAPILocked: Bool {
        apiService.isLocked
    }

    /// Re-reads manual recovery from disk / defaults (e.g. after relaunch in tests).
    internal func testingRefreshManualRecoveryFromDisk() {
        refreshManualRecoveryFromDisk()
    }

    /// Package tests: persist manual recovery as after a failed rollback.
    internal func testingArmManualRecoveryForTests(_ message: String) {
        setupRequiresManualRecoveryReason = message
        setupError = message
        Self.persistManualRecoveryFlag(message)
    }

    func start() {
        apiService.setLocked(true)
        presentation = .loading
        Task {
            // Defer bind until after app finish-launching so FlyingFox accepts the port.
            AkashicAPIBootstrap.startLockedOnly(apiService: apiService)
            await evaluateVaultState()
        }
    }

    private func evaluateVaultState() async {
        refreshManualRecoveryFromDisk()
        if setupRequiresManualRecoveryReason != nil {
            presentation = .firstRun
            return
        }
        do {
            if let hazard = try SetupMigrationHazardDetector.blockingReasonIfPresent(), !hazard.isEmpty {
                setupRequiresManualRecoveryReason = hazard
                setupError = hazard
                Self.persistManualRecoveryFlag(hazard)
                presentation = .firstRun
                return
            }
        } catch {
            setupError = error.localizedDescription
            presentation = .unlock
            return
        }
        do {
            let dbURL = try AkashicPaths.databaseURL()
            if let metadata = try LocalSecurityMetadataStore.load() {
                unlockUsername = metadata.username
                if FileManager.default.fileExists(atPath: dbURL.path) {
                    presentation = .unlock
                } else {
                    setupError = "Security data exists but the database file is missing. Restore from backup or reinstall."
                    presentation = .unlock
                }
            } else if FileManager.default.fileExists(atPath: dbURL.path) {
                let looksPlain = try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: dbURL)
                if looksPlain {
                    presentation = .firstRun
                    resetFirstRunWizard()
                    setupError =
                        "Existing data will be encrypted. Set username and password, scan the authenticator QR, then confirm with a code."
                } else {
                    setupError = "Database exists but security metadata is missing. Restore akashic-security.json from backup."
                    presentation = .unlock
                }
            } else {
                presentation = .firstRun
                resetFirstRunWizard()
                setupError = nil
            }
        } catch {
            setupError = error.localizedDescription
            presentation = .unlock
        }
    }

    func resetFirstRunWizard() {
        if setupRequiresManualRecoveryReason != nil { return }
        firstRunStep = .credentials
        setupOtpauthURI = ""
        setupRecoveryDisplay = ""
        setupTOTPCode = ""
        pendingMetadata = nil
        pendingDataKey = nil
    }

    /// Step 1 → 2: validate credentials and generate recovery code + TOTP secret (shown once).
    func advanceFirstRunToCodes() {
        if let block = blockedByManualRecoveryMessage() {
            setupError = block
            return
        }
        setupError = nil
        let trimmedUser = setupUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUser.isEmpty else {
            setupError = "Username is required."
            return
        }
        guard setupPassword.count >= 8 else {
            setupError = "Password must be at least 8 characters."
            return
        }
        guard setupPassword == setupConfirmPassword else {
            setupError = "Passwords do not match."
            return
        }
        do {
            let (metadata, recoveryDisplay, _, otpauth) = try DataKeyManager.generateMetadata(
                username: trimmedUser,
                password: setupPassword
            )
            let dataKey = try DataKeyManager.unwrapDataKey(metadata: metadata, password: setupPassword)
            pendingMetadata = metadata
            pendingDataKey = dataKey
            setupRecoveryDisplay = recoveryDisplay
            setupOtpauthURI = otpauth
            // DoD / isolated-data helper: when AKASHIC_DATA_DIR is set, write otpauth URI
            // so automated verification can compute a TOTP without scanning the QR.
            if ProcessInfo.processInfo.environment[AkashicPaths.dataDirectoryEnvironmentKey] != nil {
                let dump = (try? AkashicPaths.applicationSupportFolder())?
                    .appendingPathComponent("dod-setup-otpauth.txt")
                if let dump {
                    let body = otpauth + "\n" + recoveryDisplay + "\n"
                    try? body.data(using: .utf8)?.write(to: dump, options: .atomic)
                }
            }
            firstRunStep = .codes
        } catch {
            setupError = error.localizedDescription
        }
    }

    func advanceFirstRunToConfirm() {
        if let block = blockedByManualRecoveryMessage() {
            setupError = block
            return
        }
        setupError = nil
        firstRunStep = .confirm
    }

    /// Confirm step → QR step without regenerating `pendingMetadata` / TOTP secret (unlike `resetFirstRunWizard()`).
    func goBackFromFirstRunConfirmToCodes() {
        if let block = blockedByManualRecoveryMessage() {
            setupError = block
            return
        }
        firstRunStep = .codes
        setupTOTPCode = ""
        setupError = nil
    }

    /// Used by package tests to compute the expected TOTP for the pending setup secrets.
    internal func testingCurrentSetupTOTPCode() throws -> String {
        guard let metadata = pendingMetadata, let dataKey = pendingDataKey else {
            struct MissingPending: Error {}
            throw MissingPending()
        }
        let secret = try DataKeyManager.openTOTPSecret(metadata: metadata, dataKey: dataKey)
        return TOTP.code(secret: secret)
    }

    /// Step 3: confirm TOTP, migrate/create DB, save sidecar, open DB. No unlock until all steps succeed.
    func completeFirstRunAfterTOTP() async {
        guard !isCompletingFirstRun else { return }
        isCompletingFirstRun = true
        defer { isCompletingFirstRun = false }

        setupError = nil
        if let block = blockedByManualRecoveryMessage() {
            setupError = block
            return
        }
        guard let metadata = pendingMetadata, let dataKey = pendingDataKey else {
            setupError = "Setup expired; go back and regenerate codes."
            return
        }

        let totpSecret: Data
        do {
            totpSecret = try DataKeyManager.openTOTPSecret(metadata: metadata, dataKey: dataKey)
        } catch {
            setupError =
                "Could not read the authenticator secret from setup data: \(error.localizedDescription)"
            return
        }

        guard let normalizedTOTP = TOTP.sanitizeEnteredCode(setupTOTPCode) else {
            setupError = "Enter a 6-digit code (digits only, or from AutoFill)."
            return
        }
        guard TOTP.validate(secret: totpSecret, code: normalizedTOTP) else {
            setupError = "Invalid authenticator code."
            return
        }

        let folder: URL
        let dbURL: URL
        do {
            folder = try AkashicPaths.applicationSupportFolder()
            dbURL = try AkashicPaths.databaseURL()
        } catch {
            setupError = "Could not access the data folder: \(error.localizedDescription)"
            return
        }

        var migrationPlaintextBackupURL: URL?
        var createdFreshEncryptedDB = false

        let dbExists = FileManager.default.fileExists(atPath: dbURL.path)
        let isPlain: Bool
        if !dbExists {
            isPlain = false
        } else {
            do {
                isPlain = try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: dbURL)
            } catch {
                setupError =
                    "Could not inspect your existing database file: \(error.localizedDescription)"
                return
            }
        }

        if isPlain {
            let tmp = folder.appendingPathComponent(".akashic-encrypt-migrate-\(UUID().uuidString).sqlite")
            do {
                try SQLiteDiskBundle.removeAllIfPresent(main: tmp)
            } catch {
                setupError =
                    "Could not prepare database encryption (temp file): \(error.localizedDescription)"
                return
            }
            do {
                try AkashicPlaintextMigration.exportPlaintextToEncrypted(
                    plaintextURL: dbURL,
                    encryptedDestinationURL: tmp,
                    dataKey: dataKey
                )
                migrationPlaintextBackupURL = try AkashicPlaintextMigration.atomicSwapPlaintextForEncrypted(
                    livePlaintextURL: dbURL,
                    encryptedTempURL: tmp,
                    backupDirectory: folder
                )
            } catch {
                try? SetupMigrationJournal.clear()
                do {
                    try SQLiteDiskBundle.removeAllIfPresent(main: tmp)
                } catch let cleanupError {
                    Self.handleManualRecoveryIfNeeded(
                        result: .failure(cleanupError),
                        setupRequiresManualRecoveryReason: &setupRequiresManualRecoveryReason,
                        setupError: &setupError,
                        detail: "cleanup temp encrypt path: \(cleanupError.localizedDescription)",
                        backupPlaintextPath: migrationPlaintextBackupURL?.path
                    )
                }
                // `atomicSwapPlaintextForEncrypted` can throw `swapAndRestoreFailed` before returning the
                // backup URL, so `migrationPlaintextBackupURL` is still nil even though a backup path exists on disk.
                if let mig = error as? AkashicMigrationError,
                   case let .swapAndRestoreFailed(backupPath, swapDetail, restoreDetail) = mig
                {
                    Self.handleManualRecoveryIfNeeded(
                        result: .failure(
                            NSError(
                                domain: "AkashicMigration",
                                code: 0,
                                userInfo: [NSLocalizedDescriptionKey: restoreDetail]
                            )
                        ),
                        setupRequiresManualRecoveryReason: &setupRequiresManualRecoveryReason,
                        setupError: &setupError,
                        detail:
                            "swap failed while encrypting the database (promoting encrypted file to live). Swap/revert detail: \(swapDetail)",
                        backupPlaintextPath: backupPath
                    )
                }
                if let backup = migrationPlaintextBackupURL {
                    Self.handleManualRecoveryIfNeeded(
                        result: Result { try rollbackPlaintextMigration(liveDB: dbURL, backupURL: backup) },
                        setupRequiresManualRecoveryReason: &setupRequiresManualRecoveryReason,
                        setupError: &setupError,
                        detail: error.localizedDescription,
                        backupPlaintextPath: backup.path
                    )
                    migrationPlaintextBackupURL = nil
                }
                if setupRequiresManualRecoveryReason == nil {
                    let msg = Self.migrationSetupErrorMessage(for: error)
                    setupError = msg
                    if Self.migrationFailureRequiresManualRecovery(error) {
                        setupRequiresManualRecoveryReason = msg
                        Self.persistManualRecoveryFlag(msg)
                    }
                }
                return
             }
        } else if !dbExists {
            do {
                try Self.createEncryptedEmptyAtomically(at: dbURL, passphrase: dataKey)
                createdFreshEncryptedDB = true
            } catch {
                setupError =
                    "Could not create the encrypted database: \(error.localizedDescription)"
                return
            }
        } else {
            setupError =
                "An encrypted database already exists but security metadata is missing. Restore akashic-security.json or remove the stray akashic.sqlite after backup."
            return
        }

        do {
            try LocalSecurityMetadataStore.save(metadata)
        } catch {
            let rollback = Result {
                try undoFirstRunDiskStateAfterMetadataSaveFailure(
                    dbURL: dbURL,
                    migrationPlaintextBackupURL: migrationPlaintextBackupURL,
                    createdFreshEncryptedDB: createdFreshEncryptedDB
                )
            }
            Self.handleManualRecoveryIfNeeded(
                result: rollback,
                setupRequiresManualRecoveryReason: &setupRequiresManualRecoveryReason,
                setupError: &setupError,
                detail: error.localizedDescription,
                backupPlaintextPath: migrationPlaintextBackupURL?.path
            )
            if setupRequiresManualRecoveryReason == nil {
                setupError =
                    "Could not save security metadata (akashic-security.json): \(error.localizedDescription)"
            }
            return
        }

        do {
            try finishUnlock(dataKey: dataKey, metadata: metadata)
        } catch {
            let rollback = Result {
                try undoFirstRunAfterMetadataButBeforeUnlock(
                    dbURL: dbURL,
                    migrationPlaintextBackupURL: migrationPlaintextBackupURL,
                    createdFreshEncryptedDB: createdFreshEncryptedDB
                )
            }
            Self.handleManualRecoveryIfNeeded(
                result: rollback,
                setupRequiresManualRecoveryReason: &setupRequiresManualRecoveryReason,
                setupError: &setupError,
                detail: error.localizedDescription,
                backupPlaintextPath: migrationPlaintextBackupURL?.path
            )
            if setupRequiresManualRecoveryReason == nil {
                setupError =
                    "Could not open the encrypted database: \(error.localizedDescription)"
            }
            return
        }

        try? SetupManualRecoveryStore.clear()
        try? SetupMigrationJournal.clear()
        setupRequiresManualRecoveryReason = nil

        pendingMetadata = nil
        pendingDataKey = nil
    }

    private func rollbackPlaintextMigration(liveDB: URL, backupURL: URL) throws {
        try SQLiteDiskBundle.moveBundle(from: backupURL, to: liveDB)
    }

    private func undoFirstRunDiskStateAfterMetadataSaveFailure(
        dbURL: URL,
        migrationPlaintextBackupURL: URL?,
        createdFreshEncryptedDB: Bool
    ) throws {
        if let backup = migrationPlaintextBackupURL {
            try rollbackPlaintextMigration(liveDB: dbURL, backupURL: backup)
        } else if createdFreshEncryptedDB {
            try SQLiteDiskBundle.removeAllIfPresent(main: dbURL)
        }
        try LocalSecurityMetadataStore.deleteIfPresent()
    }

    private func undoFirstRunAfterMetadataButBeforeUnlock(
        dbURL: URL,
        migrationPlaintextBackupURL: URL?,
        createdFreshEncryptedDB: Bool
    ) throws {
        try LocalSecurityMetadataStore.deleteIfPresent()
        if let backup = migrationPlaintextBackupURL {
            try SQLiteDiskBundle.removeAllIfPresent(main: dbURL)
            try SQLiteDiskBundle.moveBundle(from: backup, to: dbURL)
        } else if createdFreshEncryptedDB {
            try SQLiteDiskBundle.removeAllIfPresent(main: dbURL)
        }
    }

    private static func migrationSetupErrorMessage(for error: Error) -> String {
        if let bundle = error as? AkashicSQLiteBundleError {
            switch bundle {
            case .walCheckpointBusy:
                return "Could not prepare your existing database for encryption: the database is busy (another app or window has it open). Close other connections and try again."
            case let .walCheckpointIncomplete(remainingLogPages):
                return "Could not prepare your existing database for encryption: WAL could not be fully checkpointed (\(remainingLogPages) log pages left). Close other connections and try again."
            case let .walCheckpointFailed(reason):
                return "Could not prepare your existing database for encryption: \(reason)"
            case let .bundleMoveUnwindFailed(originalDescription, unwindDescription):
                return "Could not encrypt or replace your existing database (partial file move then unwind failed). Original: \(originalDescription). Unwind: \(unwindDescription). Check the Akashic data folder."
            case .simulatedMoveFailure:
                return "Could not encrypt or replace your existing database: \(error.localizedDescription)"
            }
        }
        if let mig = error as? AkashicMigrationError, case let .swapAndRestoreFailed(backupPath, swapDetail, restoreDetail) = mig {
            return "Could not finish encrypting your database (swap failed). Plaintext backup may be at: \(backupPath). Swap: \(swapDetail). Restore attempt: \(restoreDetail)"
        }
        if let mig = error as? AkashicMigrationError, case .missingMigrationJournal = mig {
            return "Could not encrypt or replace your existing database: migration journal missing or inconsistent. Do not retry until files are reconciled."
        }
        return "Could not encrypt or replace your existing database: \(error.localizedDescription)"
    }

    private static func migrationFailureRequiresManualRecovery(_ error: Error) -> Bool {
        if let b = error as? AkashicSQLiteBundleError {
            switch b {
            case .bundleMoveUnwindFailed:
                return true
            case .walCheckpointBusy, .walCheckpointIncomplete, .walCheckpointFailed, .simulatedMoveFailure:
                return false
            }
        }
        if let m = error as? AkashicMigrationError {
            switch m {
            case .swapAndRestoreFailed, .missingMigrationJournal:
                return true
            case .rowCountMismatch, .missingTempEncrypted:
                return false
            }
        }
        return false
    }

    /// Creates `akashic.sqlite` (and sidecars) in one shot; removes partial files on failure.
    private static func createEncryptedEmptyAtomically(at dbURL: URL, passphrase: Data) throws {
        let tmp = dbURL.deletingLastPathComponent()
            .appendingPathComponent(".akashic-new-encrypted-\(UUID().uuidString).sqlite")
        do {
            let q = try TodoDatabase.createEncryptedEmpty(at: tmp, passphrase: passphrase)
            try q.close()
            try SQLiteDiskBundle.moveBundle(from: tmp, to: dbURL)
        } catch {
            try? SQLiteDiskBundle.removeAllIfPresent(main: tmp)
            throw error
        }
    }

    private static func handleManualRecoveryIfNeeded(
        result: Result<Void, Error>,
        setupRequiresManualRecoveryReason: inout String?,
        setupError: inout String?,
        detail: String,
        backupPlaintextPath: String? = nil
    ) {
        switch result {
        case .success:
            break
        case .failure(let rollbackError):
            let backupNote = backupPlaintextPath.map { " Plaintext backup (if present): \($0)." } ?? ""
            let message =
                "Setup could not roll back safely after: \(detail). Rollback error: \(rollbackError.localizedDescription).\(backupNote) Check the Akashic data folder; remove akashic-setup-manual-recovery.txt only after reconciling files or restoring from backup."
            setupRequiresManualRecoveryReason = message
            setupError = message
            persistManualRecoveryFlag(message)
        }
    }

    private func refreshManualRecoveryFromDisk() {
        if let fileReason = try? SetupManualRecoveryStore.loadReason(), !fileReason.isEmpty {
            setupRequiresManualRecoveryReason = fileReason
            setupError = fileReason
        }
    }

    private func blockedByManualRecoveryMessage() -> String? {
        if let r = setupRequiresManualRecoveryReason, !r.isEmpty { return r }
        if let fileReason = try? SetupManualRecoveryStore.loadReason(), !fileReason.isEmpty {
            setupRequiresManualRecoveryReason = fileReason
            return fileReason
        }
        return nil
    }

    private static func persistManualRecoveryFlag(_ message: String) {
        do {
            try SetupManualRecoveryStore.saveReason(message)
        } catch {
            try? SetupManualRecoveryUserDefaultsStore.saveReason(message)
        }
    }

    func unlock() async {
        unlockError = nil
        guard let metadata = try? LocalSecurityMetadataStore.load() else {
            unlockError = "Missing security metadata."
            return
        }
        do {
            let dataKey = try DataKeyManager.unwrapDataKey(metadata: metadata, password: unlockPassword)
            let totpSecret = try DataKeyManager.openTOTPSecret(metadata: metadata, dataKey: dataKey)
            guard let totpNorm = TOTP.sanitizeEnteredCode(unlockTOTP) else {
                unlockError = "Enter a 6-digit code (digits only, or from AutoFill)."
                return
            }
            guard TOTP.validate(secret: totpSecret, code: totpNorm) else {
                unlockError = "Invalid authenticator code."
                return
            }
            try finishUnlock(dataKey: dataKey, metadata: metadata)
        } catch {
            unlockError = "Unlock failed: \(error.localizedDescription)"
        }
    }

    /// Recovery code replaces the password; TOTP is still required (secret sealed under data key).
    func unlockWithRecovery() async {
        unlockError = nil
        guard let metadata = try? LocalSecurityMetadataStore.load() else {
            unlockError = "Missing security metadata."
            return
        }
        do {
            let dataKey = try DataKeyManager.unwrapDataKey(metadata: metadata, recoveryCode: unlockRecoveryCode)
            let totpSecret = try DataKeyManager.openTOTPSecret(metadata: metadata, dataKey: dataKey)
            guard let totpNorm = TOTP.sanitizeEnteredCode(unlockTOTP) else {
                unlockError = "Enter a 6-digit code (digits only, or from AutoFill)."
                return
            }
            guard TOTP.validate(secret: totpSecret, code: totpNorm) else {
                unlockError = "Invalid authenticator code."
                return
            }
            try finishUnlock(dataKey: dataKey, metadata: metadata)
            unlockRecoveryCode = ""
        } catch {
            unlockError = "Recovery unlock failed."
        }
    }

    func unlockWithBiometrics() async {
        unlockError = nil
        guard biometricUnlockEnabled else { return }
        guard let metadata = try? LocalSecurityMetadataStore.load() else {
            unlockError = "Missing security metadata."
            return
        }
        do {
            let dataKey = try await AkashicKeychain.readDataKeyWithBiometry(
                reason: "Unlock Akashic"
            )
            let totpSecret = try DataKeyManager.openTOTPSecret(metadata: metadata, dataKey: dataKey)
            guard let totpNorm = TOTP.sanitizeEnteredCode(unlockTOTP) else {
                unlockError = "Enter a 6-digit code (digits only, or from AutoFill)."
                return
            }
            guard TOTP.validate(secret: totpSecret, code: totpNorm) else {
                unlockError = "Invalid authenticator code."
                return
            }
            try finishUnlock(dataKey: dataKey, metadata: metadata)
        } catch {
            unlockError = "Biometric unlock failed."
        }
    }

    func lock() {
        todoStore = nil
        noteStore = nil
        presentation = .unlock
        unlockPassword = ""
        unlockTOTP = ""
        unlockRecoveryCode = ""
        unlockError = nil
        apiService.setLocked(true)
        // Keep localhost API up: /health 200, /api/* 423 (no DB handles).
        AkashicAPIBootstrap.startLockedOnly(apiService: apiService)
        idleMonitor?.stop()
        idleMonitor = nil
    }

    func updateBiometricPreference(enabled: Bool) {
        biometricUnlockEnabled = enabled
        if !enabled {
            try? AkashicKeychain.deleteDataKey()
        }
    }

    func changePassword(oldPassword: String, newPassword: String, confirmPassword: String) throws {
        guard let metadata = try LocalSecurityMetadataStore.load() else {
            throw AkashicCryptoError.invalidInput
        }
        guard newPassword.count >= 8 else {
            throw AkashicCryptoError.invalidInput
        }
        guard newPassword == confirmPassword else {
            throw AkashicCryptoError.invalidInput
        }
        let _ = try DataKeyManager.unwrapDataKey(metadata: metadata, password: oldPassword)
        let updated = try DataKeyManager.changePassword(
            metadata: metadata,
            oldPassword: oldPassword,
            newPassword: newPassword
        )
        try LocalSecurityMetadataStore.save(updated)
    }

    private func finishUnlock(
        dataKey: Data,
        metadata: LocalSecurityMetadata
    ) throws {
        let dbURL = try AkashicPaths.databaseURL()
        let db = try TodoDatabase.openEncrypted(at: dbURL, passphrase: dataKey)
        let todo = TodoStore(db: db)
        let note = NoteStore(db: db)
        todo.runFirstLaunchSeedIfNeeded()
        todoStore = todo
        noteStore = note
        presentation = .ready
        apiService.setLocked(false)
        configureAutoLockAndSleep()
        unlockError = nil
        setupError = nil
        if biometricUnlockEnabled {
            try? AkashicKeychain.saveDataKeyForBiometry(dataKey)
        }
    }

    private func configureAutoLockAndSleep() {
        idleMonitor?.stop()
        idleMonitor = IdleTimeLockMonitor()
        idleMonitor?.start(minutes: autoLockIdleMinutes) { [weak self] in
            MainActor.assumeIsolated {
                NotificationCenter.default.post(name: .akashicRequestLock, object: nil)
            }
        }

        for o in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        sleepObservers = [
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                NotificationCenter.default.post(name: .akashicRequestLock, object: nil)
            },
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { _ in
                NotificationCenter.default.post(name: .akashicRequestLock, object: nil)
            },
        ]
    }

    deinit {
        for o in sleepObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
    }
}

// MARK: - Idle monitor

@MainActor
private final class IdleTimeLockMonitor {
    private var timer: Timer?

    func start(minutes: Int, onIdle: @escaping @Sendable () -> Void) {
        timer?.invalidate()
        guard minutes > 0 else { return }
        let threshold = TimeInterval(minutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            let idle = Self.currentIdleSeconds()
            if idle >= threshold {
                onIdle()
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    nonisolated private static func currentIdleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .null)
    }
}
