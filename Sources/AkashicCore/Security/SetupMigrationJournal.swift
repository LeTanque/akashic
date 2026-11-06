import Foundation

/// Durable first-run plaintext→encrypted migration state (under the vault folder).
/// Written **before** swapping live DB so relaunch can infer incomplete migration without metadata.
public struct SetupMigrationJournalPayload: Codable, Equatable, Sendable {
    public var version: Int
    /// `exported`: temp encrypted file is ready; live DB path still holds plaintext. `swapped`: live path holds encrypted DB; plaintext moved to `plaintextBackupFileName`.
    public enum Stage: String, Codable, Sendable {
        case exported = "exported"
        case swapped = "swapped"
    }

    public var stage: Stage
    public var tempEncryptedFileName: String?
    public var plaintextBackupFileName: String?

    public static let currentVersion = 1

    public init(version: Int, stage: Stage, tempEncryptedFileName: String?, plaintextBackupFileName: String?) {
        self.version = version
        self.stage = stage
        self.tempEncryptedFileName = tempEncryptedFileName
        self.plaintextBackupFileName = plaintextBackupFileName
    }
}

public enum SetupMigrationJournal {
    public static let filename = "akashic-setup-migration.json"

    public static func fileURL() throws -> URL {
        try AkashicPaths.applicationSupportFolder().appendingPathComponent(filename)
    }

    public static func load() throws -> SetupMigrationJournalPayload? {
        let url = try fileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SetupMigrationJournalPayload.self, from: data)
    }

    public static func save(_ payload: SetupMigrationJournalPayload) throws {
        SetupMigrationJournalTestingHooks.saveInvocationCount += 1
        if let err = SetupMigrationJournalTestingHooks.saveFailure {
            let target = SetupMigrationJournalTestingHooks.failOnSaveInvocation
            let invocation = SetupMigrationJournalTestingHooks.saveInvocationCount
            if target == nil || target == invocation {
                throw err
            }
        }
        let url = try fileURL()
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(payload)
        let tmp = folder.appendingPathComponent(".akashic-setup-migration-\(UUID().uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp, backupItemName: nil)
    }

    public static func clear() throws {
        let url = try fileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// Test hook: force journal persistence to fail (package tests).
public enum SetupMigrationJournalTestingHooks {
    public nonisolated(unsafe) static var saveFailure: Error?
    /// Incremented on each `save` attempt. When equal to `failOnSaveInvocation`, `saveFailure` is thrown (if set).
    public nonisolated(unsafe) static var saveInvocationCount: Int = 0
    public nonisolated(unsafe) static var failOnSaveInvocation: Int?
}
