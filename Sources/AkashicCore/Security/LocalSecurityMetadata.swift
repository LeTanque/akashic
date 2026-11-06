import Foundation

/// Sidecar JSON next to `akashic.sqlite`. Never stores the raw data key.
public struct LocalSecurityMetadata: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var username: String
    /// PBKDF2 salt for password → wrapping key.
    public var passwordSalt: Data
    public var passwordIterations: Int
    public var passwordWrappedDataKey: Data
    /// PBKDF2 salt for recovery code → wrapping key (same iteration budget as password).
    public var recoverySalt: Data
    public var recoveryIterations: Int
    public var recoveryWrappedDataKey: Data
    /// Raw TOTP secret bytes, sealed with the data key (ChaChaPoly combined). Server can replicate this field in sync phases.
    public var totpSecretSealed: Data

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case username
        case passwordSalt = "password_salt"
        case passwordIterations = "password_iterations"
        case passwordWrappedDataKey = "password_wrapped_data_key"
        case recoverySalt = "recovery_salt"
        case recoveryIterations = "recovery_iterations"
        case recoveryWrappedDataKey = "recovery_wrapped_data_key"
        case totpSecretSealed = "totp_secret_sealed"
    }
}

public enum LocalSecurityMetadataStore {
    public static func load(from url: URL? = nil) throws -> LocalSecurityMetadata? {
        let url = try url ?? AkashicPaths.securityMetadataURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(LocalSecurityMetadata.self, from: data)
    }

    /// Removes the sidecar file if present. Used when rolling back a failed first-run commit.
    public static func deleteIfPresent(at url: URL? = nil) throws {
        let url = try url ?? AkashicPaths.securityMetadataURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func save(_ metadata: LocalSecurityMetadata, to url: URL? = nil) throws {
        LocalSecurityMetadataStoreTestingHooks.saveEntryCount += 1
        if let err = LocalSecurityMetadataStoreTestingHooks.saveFailure {
            throw err
        }
        let delay = LocalSecurityMetadataStoreTestingHooks.saveDelayNanoseconds
        if delay > 0 {
            Thread.sleep(forTimeInterval: Double(delay) / 1_000_000_000.0)
        }
        let url = try url ?? AkashicPaths.securityMetadataURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".akashic-security-\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp, backupItemName: nil)
    }
}

/// Test-only hooks (package tests). Must remain `nil` in production code paths.
public enum LocalSecurityMetadataStoreTestingHooks {
    public nonisolated(unsafe) static var saveFailure: Error?
    /// When > 0, `save` sleeps before writing (tests duplicate Finish / concurrency).
    public nonisolated(unsafe) static var saveDelayNanoseconds: UInt64 = 0
    /// Incremented on each `save` entry (tests verify single commit).
    public nonisolated(unsafe) static var saveEntryCount: Int = 0
}

/// Test-only hooks for first-run plaintext migration (package tests).
public enum AkashicPlaintextMigrationTestingHooks {
    public nonisolated(unsafe) static var atomicSwapError: Error?
    /// When set, `exportPlaintextToEncrypted` throws this error (tests migration failure before swap).
    public nonisolated(unsafe) static var exportPlaintextFailure: Error?
}
