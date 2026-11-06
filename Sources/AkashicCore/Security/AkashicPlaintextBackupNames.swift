import Foundation

/// Shared naming for plaintext DB backups during migration (must stay in sync with tests and hazard detection).
public enum AkashicPlaintextBackupNames {
    public static let prefix = "akashic.sqlite.plaintext-backup-"

    /// Matches files produced by `plaintextBackupFilename(for:)` (timestamp suffix has no `.sqlite` extension).
    public static func isPlaintextBackupFilename(_ lastPathComponent: String) -> Bool {
        lastPathComponent.hasPrefix(prefix)
    }

    /// Same basename generation as `AkashicPlaintextMigration.atomicSwapPlaintextForEncrypted`.
    public static func plaintextBackupFilename(for date: Date = Date()) -> String {
        let ts = ISO8601DateFormatter().string(from: date).replacingOccurrences(of: ":", with: "-")
        return "\(prefix)\(ts)"
    }
}
