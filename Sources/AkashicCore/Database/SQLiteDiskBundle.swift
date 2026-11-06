import Foundation
import GRDB

/// Test-only (package tests).
public enum SQLiteDiskBundleTestingHooks {
    public nonisolated(unsafe) static var moveBundleFailure: Error?
}

/// Paths for a single SQLite "database file" which may include `-wal` and `-shm` sidecars.
public enum SQLiteDiskBundle {
    public static func journalURL(forMainDB main: URL) -> URL {
        main.deletingPathExtension().appendingPathExtension("sqlite-journal")
    }

    public static func walURL(forMainDB main: URL) -> URL {
        main.deletingPathExtension().appendingPathExtension("sqlite-wal")
    }

    public static func shmURL(forMainDB main: URL) -> URL {
        main.deletingPathExtension().appendingPathExtension("sqlite-shm")
    }

    /// Files that may exist alongside `main` for rollback / cleanup.
    public static func possibleSidecarURLs(main: URL) -> [URL] {
        [journalURL(forMainDB: main), walURL(forMainDB: main), shmURL(forMainDB: main)]
    }

    public static func removeAllIfPresent(main: URL) throws {
        let urls = [main] + possibleSidecarURLs(main: main)
        for u in urls where FileManager.default.fileExists(atPath: u.path) {
            try FileManager.default.removeItem(at: u)
        }
    }

    /// Move main DB and any existing sidecars; does not create missing sidecars.
    public static func moveBundle(from sourceMain: URL, to destMain: URL) throws {
        if let err = SQLiteDiskBundleTestingHooks.moveBundleFailure {
            throw err
        }
        let pairs: [(URL, URL)] = [
            (sourceMain, destMain),
            (journalURL(forMainDB: sourceMain), journalURL(forMainDB: destMain)),
            (walURL(forMainDB: sourceMain), walURL(forMainDB: destMain)),
            (shmURL(forMainDB: sourceMain), shmURL(forMainDB: destMain)),
        ]
        for (src, dst) in pairs {
            guard FileManager.default.fileExists(atPath: src.path) else { continue }
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.moveItem(at: src, to: dst)
        }
    }

    /// Checkpoint WAL into the main file and close, so only the `-wal` file needs moving (often empty/absent).
    public static func checkpointWALAndClosePlainDatabase(at main: URL) throws {
        var config = Configuration()
        config.label = "AkashicCheckpointPlain"
        let queue = try DatabaseQueue(path: main.path, configuration: config)
        try queue.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
        try queue.close()
    }
}
