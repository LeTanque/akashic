import Foundation

/// Persists "finish setup cannot safely retry" across navigation and process restarts.
/// Scoped to the vault data folder (respects `AKASHIC_DATA_DIR`).
public enum SetupManualRecoveryStore {
    public static let filename = "akashic-setup-manual-recovery.txt"
    public static let emergencyFilename = "akashic-setup-manual-recovery.emergency.txt"

    public static func fileURL() throws -> URL {
        try AkashicPaths.applicationSupportFolder().appendingPathComponent(filename)
    }

    public static func emergencyFileURL() throws -> URL {
        try AkashicPaths.applicationSupportFolder().appendingPathComponent(emergencyFilename)
    }

    public static func loadReason() throws -> String? {
        let primary = try fileURL()
        if FileManager.default.fileExists(atPath: primary.path) {
            return try String(contentsOf: primary, encoding: .utf8)
        }
        let emerg = try emergencyFileURL()
        if FileManager.default.fileExists(atPath: emerg.path) {
            return try String(contentsOf: emerg, encoding: .utf8)
        }
        if let ud = SetupManualRecoveryUserDefaultsStore.loadReason(), !ud.isEmpty {
            return ud
        }
        return nil
    }

    public static func saveReason(_ message: String) throws {
        if let err = SetupManualRecoveryStoreTestingHooks.primarySaveFailure {
            throw err
        }
        let folder = try AkashicPaths.applicationSupportFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = message.data(using: .utf8) else {
            throw AkashicCryptoError.invalidInput
        }
        let primary = try fileURL()
        let emerg = try emergencyFileURL()

        var wroteToDisk = false
        do {
            try data.write(to: primary, options: .atomic)
            if FileManager.default.fileExists(atPath: emerg.path) {
                try FileManager.default.removeItem(at: emerg)
            }
            wroteToDisk = true
        } catch {
            do {
                try data.write(to: emerg, options: .atomic)
                wroteToDisk = true
            } catch let emergErr {
                try SetupManualRecoveryUserDefaultsStore.saveReason(message)
                throw emergErr
            }
        }

        if wroteToDisk {
            try? SetupManualRecoveryUserDefaultsStore.saveReason(message)
        }
    }

    public static func clear() throws {
        for url in try [fileURL(), emergencyFileURL()] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        try SetupManualRecoveryUserDefaultsStore.clear()
    }
}

/// Test-only hooks (package tests).
public enum SetupManualRecoveryStoreTestingHooks {
    public nonisolated(unsafe) static var primarySaveFailure: Error?
}
