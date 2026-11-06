import Foundation
import GRDB

public struct AppMetaRecord: FetchableRecord, PersistableRecord, TableRecord {
    public static let databaseTableName = "app_meta"

    enum Columns: String, ColumnExpression {
        case key
        case value
    }

    var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

/// Per-installation sync identity and HLC source (persisted `deviceId` in SQLite).
public final class InstallationContext: @unchecked Sendable {
    public static let deviceIdKey = "device_id"

    public let deviceId: UUID
    public let clock: HybridLogicalClockSource

    public init(deviceId: UUID) {
        self.deviceId = deviceId
        self.clock = HybridLogicalClockSource(deviceId: deviceId)
    }

    /// Loads or creates `deviceId` in `app_meta` (must run inside `db.write`).
    public static func loadOrCreate(in db: Database) throws -> InstallationContext {
        let sql = "SELECT * FROM \(AppMetaRecord.databaseTableName) WHERE key = ?"
        if let row = try AppMetaRecord.fetchOne(db, sql: sql, arguments: [Self.deviceIdKey]),
           let id = UUID(uuidString: row.value) {
            return InstallationContext(deviceId: id)
        }
        let id = UUID()
        try AppMetaRecord(key: Self.deviceIdKey, value: id.uuidString).insert(db)
        return InstallationContext(deviceId: id)
    }

    @discardableResult
    public func tick() -> HybridLogicalClock {
        clock.tick()
    }

    public func freshTodo(
        title: String = "",
        description: String = "",
        priority: TodoPriority = .medium
    ) -> TodoItem {
        let c = clock.tick()
        return TodoItem.new(title: title, description: description, priority: priority, deviceId: deviceId, clock: c)
    }

    public func freshNote(
        title: String = "",
        body: String = "",
        tags: [AkashicTag] = []
    ) -> NoteItem {
        let c = clock.tick()
        return NoteItem.new(title: title, body: body, tags: tags, deviceId: deviceId, clock: c)
    }
}
