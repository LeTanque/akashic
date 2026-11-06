import AkashicCore
import AppKit
import Combine
import CoreGraphics
import Foundation
import GRDB

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
        firstRunStep = .credentials
        setupOtpauthURI = ""
        setupRecoveryDisplay = ""
        setupTOTPCode = ""
        pendingMetadata = nil
        pendingDataKey = nil
    }

    /// Step 1 → 2: validate credentials and generate recovery code + TOTP secret (shown once).
    func advanceFirstRunToCodes() {
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
        setupError = nil
        firstRunStep = .confirm
    }

    /// Step 3: confirm TOTP, persist metadata, migrate plaintext if needed, open DB.
    func completeFirstRunAfterTOTP() async {
        setupError = nil
        guard let metadata = pendingMetadata, let dataKey = pendingDataKey else {
            setupError = "Setup expired; go back and regenerate codes."
            return
        }
        do {
            let totpSecret = try DataKeyManager.openTOTPSecret(metadata: metadata, dataKey: dataKey)
            guard TOTP.validate(secret: totpSecret, code: setupTOTPCode) else {
                setupError = "Invalid authenticator code."
                return
            }

            let folder = try AkashicPaths.applicationSupportFolder()
            let dbURL = try AkashicPaths.databaseURL()

            if FileManager.default.fileExists(atPath: dbURL.path),
               try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: dbURL)
            {
                let tmp = folder.appendingPathComponent(".akashic-encrypt-migrate-\(UUID().uuidString).sqlite")
                if FileManager.default.fileExists(atPath: tmp.path) {
                    try FileManager.default.removeItem(at: tmp)
                }
                do {
                    try AkashicPlaintextMigration.exportPlaintextToEncrypted(
                        plaintextURL: dbURL,
                        encryptedDestinationURL: tmp,
                        dataKey: dataKey
                    )
                    try AkashicPlaintextMigration.atomicSwapPlaintextForEncrypted(
                        livePlaintextURL: dbURL,
                        encryptedTempURL: tmp,
                        backupDirectory: folder
                    )
                } catch {
                    try? FileManager.default.removeItem(at: tmp)
                    setupError = error.localizedDescription
                    return
                }
            } else if !FileManager.default.fileExists(atPath: dbURL.path) {
                _ = try TodoDatabase.createEncryptedEmpty(at: dbURL, passphrase: dataKey)
            } else {
                setupError = "Database already exists in an unknown format."
                return
            }

            try LocalSecurityMetadataStore.save(metadata)
            pendingMetadata = nil
            pendingDataKey = nil
            try finishUnlock(dataKey: dataKey, metadata: metadata)
        } catch {
            setupError = error.localizedDescription
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
            guard TOTP.validate(secret: totpSecret, code: unlockTOTP) else {
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
            guard TOTP.validate(secret: totpSecret, code: unlockTOTP) else {
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
            guard TOTP.validate(secret: totpSecret, code: unlockTOTP) else {
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
