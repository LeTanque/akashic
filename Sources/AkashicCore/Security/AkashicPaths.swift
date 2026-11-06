import Foundation

/// Files under Application Support / `Akashic` (same relative layout on macOS and iOS).
///
/// **Isolation / DoD:** set environment variable `AKASHIC_DATA_DIR` to an absolute directory
/// to redirect the vault folder (database + `akashic-security.json`) away from the default
/// Application Support path. Used for migration dry-runs; leave unset for production.
public enum AkashicPaths {
    public static let folderName = "Akashic"
    public static let databaseFilename = "akashic.sqlite"
    public static let securityMetadataFilename = "akashic-security.json"
    public static let dataDirectoryEnvironmentKey = "AKASHIC_DATA_DIR"

    public static func applicationSupportFolder() throws -> URL {
        if let override = ProcessInfo.processInfo.environment[dataDirectoryEnvironmentKey],
           !override.isEmpty {
            let folder = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = appSupport.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    public static func databaseURL() throws -> URL {
        try applicationSupportFolder().appendingPathComponent(databaseFilename)
    }

    /// Sidecar for wrapped keys, KDF params, sealed TOTP secret (no raw DB key).
    public static func securityMetadataURL() throws -> URL {
        try applicationSupportFolder().appendingPathComponent(securityMetadataFilename)
    }
}
