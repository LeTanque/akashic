import Foundation

/// Persists "finish setup cannot safely retry" across navigation and process restarts.
/// Scoped to the vault data folder (respects `AKASHIC_DATA_DIR`).
public enum SetupManualRecoveryStore {
    public static let filename = "akashic-setup-manual-recovery.txt"

    public static func fileURL() throws -> URL {
        try AkashicPaths.applicationSupportFolder().appendingPathComponent(filename)
    }

    public static func loadReason() throws -> String? {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func saveReason(_ message: String) throws {
        let url = try fileURL()
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let data = message.data(using: .utf8) else {
            throw AkashicCryptoError.invalidInput
        }
        try data.write(to: url, options: .atomic)
    }

    public static func clear() throws {
        let url = try fileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
