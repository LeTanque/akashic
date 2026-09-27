import Foundation
import SQLite3

/// Read-only access to Cursor IDE `state.vscdb` (copied to a temp dir so WAL files stay consistent).
enum CursorStateDatabase {
    static func value(forKey key: String) -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-cursor", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let copy = tempDir.appendingPathComponent("state.vscdb")
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: url.path + suffix)
            let dest = URL(fileURLWithPath: copy.path + suffix)
            guard fm.fileExists(atPath: source.path) else { continue }
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: source, to: dest)
        }

        let dbURL = fm.fileExists(atPath: copy.path) ? copy : url
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK, db != nil else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        let escaped = key.replacingOccurrences(of: "'", with: "''")
        for table in ["ItemTable", "cursorDiskKV"] {
            let sql = "SELECT value FROM \(table) WHERE key = '\(escaped)' LIMIT 1"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { continue }
            if let pointer = sqlite3_column_text(statement, 0) {
                let value = String(cString: pointer)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }
}
