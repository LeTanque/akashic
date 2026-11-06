import Foundation

/// Detects inconsistent first-run migration state on disk when **security metadata is absent**.
public enum SetupMigrationHazardDetector {
    /// When non-nil, first-run setup must block until disk is reconciled (message is shown; persist manual recovery when appropriate).
    public static func blockingReasonIfPresent() throws -> String? {
        if let reason = try SetupManualRecoveryStore.loadReason(), !reason.isEmpty {
            return reason
        }

        guard try LocalSecurityMetadataStore.load() == nil else { return nil }

        let folder = try AkashicPaths.applicationSupportFolder()
        let dbURL = try AkashicPaths.databaseURL()
        let dbExists = FileManager.default.fileExists(atPath: dbURL.path)

        guard let journal = try SetupMigrationJournal.load() else {
            if let s = strayTempWithoutMetadata(folder: folder) { return s }
            return orphanedPlaintextBackupWithoutLiveDb(folder: folder, dbURL: dbURL, dbExists: dbExists)
        }

        let tempName = journal.tempEncryptedFileName ?? ""
        let backupName = journal.plaintextBackupFileName ?? ""
        let tempURL = folder.appendingPathComponent(tempName)
        let backupURL = folder.appendingPathComponent(backupName)
        let hasTemp = !tempName.isEmpty && FileManager.default.fileExists(atPath: tempURL.path)
        let hasBackup = !backupName.isEmpty && FileManager.default.fileExists(atPath: backupURL.path)

        switch journal.stage {
        case .exported:
            if hasTemp, dbExists, try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: dbURL) {
                return nil
            }
            return
                "Incomplete database encryption (export stage). The vault folder may be inconsistent. Inspect akashic-setup-migration.json and temp files; restore from backup if needed."

        case .swapped:
            if !dbExists, hasBackup {
                return
                    "Incomplete database encryption: live `akashic.sqlite` is missing but plaintext backup exists at \(backupURL.path). Restore that backup to `akashic.sqlite` after reconciling, or copy data safely, then remove akashic-setup-migration.json."
            }
            if !dbExists, !hasBackup {
                return
                    "Incomplete database encryption: live database missing and no plaintext backup found. Restore from backup."
            }
            if dbExists, hasBackup, try AkashicPlaintextMigration.fileLooksLikePlaintextSQLite(at: dbURL) {
                return
                    "Incomplete database encryption: live file is still plaintext while migration journal says swap completed. Manual recovery required; see \(backupURL.path) and akashic-setup-migration.json."
            }
            return nil
        }
    }

    private static func strayTempWithoutMetadata(folder: URL) -> String? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return nil
        }
        let strayEncrypt = entries.contains { $0.lastPathComponent.hasPrefix(".akashic-encrypt-migrate-") }
        if strayEncrypt {
            return "Stray encryption temp files exist without security metadata. Remove `.akashic-encrypt-migrate-*` after backup or complete setup."
        }
        let strayNewEncrypted = entries.contains { $0.lastPathComponent.hasPrefix(".akashic-new-encrypted-") }
        if strayNewEncrypted {
            return "Stray encrypted database temp files exist without security metadata. Remove `.akashic-new-encrypted-*` after backup or complete setup."
        }
        return nil
    }

    /// Without metadata, a retained `akashic.sqlite.plaintext-backup-*` but no live DB means data was stranded—do not offer an empty vault.
    private static func orphanedPlaintextBackupWithoutLiveDb(folder: URL, dbURL: URL, dbExists: Bool) -> String? {
        guard !dbExists else { return nil }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return nil
        }
        let backups = entries.filter { name in
            let n = name.lastPathComponent
            return n.hasPrefix("akashic.sqlite.plaintext-backup-") && n.hasSuffix(".sqlite")
        }
        guard let first = backups.first else { return nil }
        return
            "A plaintext database backup exists at \(first.path) but `akashic.sqlite` is missing and security metadata is absent. Restore or reconcile files before continuing; do not create a new vault over stranded data."
    }
}
