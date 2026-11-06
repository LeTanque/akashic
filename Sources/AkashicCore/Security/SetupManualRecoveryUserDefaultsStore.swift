import Foundation

/// Secondary latch when the vault folder cannot persist `akashic-setup-manual-recovery.txt` (package tests / rare disk errors).
public enum SetupManualRecoveryUserDefaultsStore {
    private static func storageKey() throws -> String {
        let folder = try AkashicPaths.applicationSupportFolder().path
        return "akashic.setup.manualRecovery.reason.\(folder.hashValue)"
    }

    public static func saveReason(_ message: String) throws {
        UserDefaults.standard.set(message, forKey: try storageKey())
    }

    public static func loadReason() -> String? {
        guard let key = try? storageKey() else { return nil }
        return UserDefaults.standard.string(forKey: key)
    }

    public static func clear() throws {
        UserDefaults.standard.removeObject(forKey: try storageKey())
    }
}
