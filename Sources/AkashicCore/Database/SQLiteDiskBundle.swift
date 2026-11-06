import Foundation
import GRDB

/// Test-only (package tests).
public enum SQLiteDiskBundleTestingHooks {
    /// When non-nil, `moveBundle` throws after exactly this many successful `moveItem` calls (1 = fail after main).
    public nonisolated(unsafe) static var moveBundleFailAfterNSuccessfulMoves: Int? = nil
    /// When set, `unwindPartialBundleMoves` throws (simulates irrecoverable partial move).
    public nonisolated(unsafe) static var unwindFailure: Error?
}

/// Paths for a single SQLite database path `*.sqlite`: sidecars are **`path-wal`**, **`path-shm`**, **`path-journal`** (not path-extension swaps).
public enum SQLiteDiskBundle {
    public static func journalURL(main: URL) -> URL {
        URL(fileURLWithPath: main.path + "-journal", isDirectory: false)
    }

    public static func walURL(main: URL) -> URL {
        URL(fileURLWithPath: main.path + "-wal", isDirectory: false)
    }

    public static func shmURL(main: URL) -> URL {
        URL(fileURLWithPath: main.path + "-shm", isDirectory: false)
    }

    public static func sidecarURLs(main: URL) -> [URL] {
        [journalURL(main: main), walURL(main: main), shmURL(main: main)]
    }

    public static func allRelatedURLs(main: URL) -> [URL] {
        [main] + sidecarURLs(main: main)
    }

    public static func removeAllIfPresent(main: URL) throws {
        for u in allRelatedURLs(main: main) where FileManager.default.fileExists(atPath: u.path) {
            try FileManager.default.removeItem(at: u)
        }
    }

    /// For **WAL** databases: run `PRAGMA wal_checkpoint(TRUNCATE)` and require `busy=0` and `log=0`.
    /// For **DELETE/TRUNCATE/OFF** journals SQLite returns `(0,-1,-1)` — that is valid; we no-op.
    public static func requireTruncatingWalCheckpointIfWAL(_ db: Database) throws {
        guard let mode = try String.fetchOne(db, sql: "PRAGMA journal_mode") else {
            throw AkashicSQLiteBundleError.walCheckpointFailed(reason: "PRAGMA journal_mode returned no row")
        }
        guard mode.lowercased() == "wal" else { return }

        guard let row = try Row.fetchOne(db, sql: "PRAGMA wal_checkpoint(TRUNCATE)") else {
            throw AkashicSQLiteBundleError.walCheckpointFailed(reason: "PRAGMA wal_checkpoint returned no row")
        }
        // Column names: busy, log, checkpointed (SQLite 3)
        let busy: Int64 = row["busy"]
        let logPages: Int64 = row["log"]
        if busy != 0 {
            throw AkashicSQLiteBundleError.walCheckpointBusy
        }
        if logPages != 0 {
            throw AkashicSQLiteBundleError.walCheckpointIncomplete(remainingLogPages: logPages)
        }
    }

    /// Move main + any existing sidecars from `sourceMain` to `destMain` in one logical step: on failure, reverse completed moves.
    public static func moveBundle(from sourceMain: URL, to destMain: URL) throws {
        let pairs: [(URL, URL)] = [
            (sourceMain, destMain),
            (journalURL(main: sourceMain), journalURL(main: destMain)),
            (walURL(main: sourceMain), walURL(main: destMain)),
            (shmURL(main: sourceMain), shmURL(main: destMain)),
        ]
        var completedMoves: [(src: URL, dst: URL)] = []
        let fm = FileManager.default
        var moveCount = 0
        do {
            for (src, dst) in pairs {
                guard fm.fileExists(atPath: src.path) else { continue }
                if fm.fileExists(atPath: dst.path) {
                    try fm.removeItem(at: dst)
                }
                try fm.moveItem(at: src, to: dst)
                completedMoves.append((src, dst))
                moveCount += 1
                if let failAfter = SQLiteDiskBundleTestingHooks.moveBundleFailAfterNSuccessfulMoves, moveCount == failAfter {
                    throw AkashicSQLiteBundleError.simulatedMoveFailure
                }
            }
        } catch let original {
            do {
                try unwindPartialBundleMoves(completedMoves)
            } catch let unwindErr {
                throw AkashicSQLiteBundleError.bundleMoveUnwindFailed(
                    originalDescription: String(describing: original),
                    unwindDescription: unwindErr.localizedDescription
                )
            }
            throw original
        }
    }

    private static func unwindPartialBundleMoves(_ completedMoves: [(src: URL, dst: URL)]) throws {
        if let err = SQLiteDiskBundleTestingHooks.unwindFailure {
            throw err
        }
        let fm = FileManager.default
        for pair in completedMoves.reversed() {
            guard fm.fileExists(atPath: pair.dst.path) else { continue }
            if fm.fileExists(atPath: pair.src.path) {
                try fm.removeItem(at: pair.src)
            }
            try fm.moveItem(at: pair.dst, to: pair.src)
        }
    }

    /// Opens the DB, truncates WAL into the main file, verifies busy/log, then closes.
    public static func checkpointWALAndClosePlainDatabase(at main: URL) throws {
        var config = Configuration()
        config.label = "AkashicCheckpointPlain"
        let queue = try DatabaseQueue(path: main.path, configuration: config)
        try queue.write { db in
            try requireTruncatingWalCheckpointIfWAL(db)
        }
        try queue.close()
    }
}

public enum AkashicSQLiteBundleError: Error, Equatable, Sendable {
    case walCheckpointBusy
    case walCheckpointIncomplete(remainingLogPages: Int64)
    case walCheckpointFailed(reason: String)
    case simulatedMoveFailure
    case bundleMoveUnwindFailed(originalDescription: String, unwindDescription: String)
}
