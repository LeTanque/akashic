import Foundation

/// Files under Application Support / `Akashic` (same relative layout on macOS and iOS).
public enum AkashicPaths {
    public static let folderName = "Akashic"
    public static let databaseFilename = "akashic.sqlite"
    public static let securityMetadataFilename = "akashic-security.json"

    public static func applicationSupportFolder() throws -> URL {
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
