import Foundation
import GRDB

public enum SyncEntity: String, Codable, Sendable {
    case todo
    case note
    case tag
    case noteTag = "note_tag"
}

public struct ChangeLogEntry: FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "change_log"

    public enum Columns: String, ColumnExpression {
        case id
        case recordID = "record_id"
        case entity
        case fieldChangesJSON = "field_changes_json"
        case hlcJSON = "hlc_json"
        case deviceID = "device_id"
        case createdAt = "created_at"
    }

    public var id: UUID
    public var recordID: String
    public var entity: SyncEntity
    public var fieldChangesJSON: String
    public var hlc: HybridLogicalClock
    public var deviceID: UUID
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        recordID: String,
        entity: SyncEntity,
        fieldChanges: [String: String],
        hlc: HybridLogicalClock,
        deviceID: UUID,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordID = recordID
        self.entity = entity
        self.fieldChangesJSON = (try? SyncJSON.encode(fieldChanges)) ?? "{}"
        self.hlc = hlc
        self.deviceID = deviceID
        self.createdAt = createdAt
    }

    public init(row: Row) {
        id = UUID(uuidString: row[Columns.id]) ?? UUID()
        recordID = row[Columns.recordID]
        entity = SyncEntity(rawValue: row[Columns.entity]) ?? .todo
        fieldChangesJSON = row[Columns.fieldChangesJSON]
        let hlcStr: String = row[Columns.hlcJSON]
        hlc = (try? SyncJSON.decode(HybridLogicalClock.self, from: hlcStr)) ?? SyncPlaceholder.draftHLC
        deviceID = UUID(uuidString: row[Columns.deviceID]) ?? UUID()
        createdAt = row[Columns.createdAt]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.recordID] = recordID
        container[Columns.entity] = entity.rawValue
        container[Columns.fieldChangesJSON] = fieldChangesJSON
        container[Columns.hlcJSON] = (try? SyncJSON.encode(hlc)) ?? "{}"
        container[Columns.deviceID] = deviceID.uuidString
        container[Columns.createdAt] = createdAt
    }
}
