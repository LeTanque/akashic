import Foundation
import GRDB

public struct TodoItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var description: String
    public var completed: Bool
    public var priority: TodoPriority
    public var completeBy: Date?
    public var createdOn: Date
    public var updatedAt: Date
    public var completedAt: Date?
    /// Stable manual list position. Lower values stack higher.
    public var sortOrder: Int

    // MARK: - Sync metadata (Phase 2)

    public var hlc: HybridLogicalClock
    public var deletedAt: Date?
    public var fieldClocks: FieldClockMap
    public var version: VersionVector

    public static func new(
        title: String = "",
        description: String = "",
        priority: TodoPriority = .medium,
        deviceId: UUID,
        clock: HybridLogicalClock
    ) -> TodoItem {
        let now = Date()
        let vv = VersionVector(map: [deviceId: clock])
        let fc = FieldClockMap(fields: [
            "title": clock,
            "description": clock,
            "completed": clock,
            "priority": clock,
            "complete_by": clock,
            "completed_at": clock,
            "sort_order": clock,
        ])
        return TodoItem(
            id: UUID(),
            title: title,
            description: description,
            completed: false,
            priority: priority,
            completeBy: nil,
            createdOn: now,
            updatedAt: now,
            completedAt: nil,
            sortOrder: 0,
            hlc: clock,
            deletedAt: nil,
            fieldClocks: fc,
            version: vv
        )
    }

    /// In-memory editor draft before first save (sync metadata is replaced on insert).
    public static func unsavedDraft(
        title: String = "",
        description: String = "",
        priority: TodoPriority = .medium
    ) -> TodoItem {
        let now = Date()
        let ph = SyncPlaceholder.draftHLC
        return TodoItem(
            id: UUID(),
            title: title,
            description: description,
            completed: false,
            priority: priority,
            completeBy: nil,
            createdOn: now,
            updatedAt: now,
            completedAt: nil,
            sortOrder: 0,
            hlc: ph,
            deletedAt: nil,
            fieldClocks: .empty,
            version: VersionVector()
        )
    }

    /// Baseline order used when assigning `sortOrder` (high → medium → low, then recency).
    public static func defaultStackOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.completed != rhs.completed { return !lhs.completed && rhs.completed }
        if lhs.priority.sortOrder != rhs.priority.sortOrder {
            return lhs.priority.sortOrder < rhs.priority.sortOrder
        }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.createdOn > rhs.createdOn
    }

    public func hasSameEditableContent(as other: TodoItem) -> Bool {
        id == other.id
            && title == other.title
            && description == other.description
            && priority == other.priority
            && completeBy == other.completeBy
    }

    public var isTombstoned: Bool { deletedAt != nil }
}

extension TodoItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "todos"

    public enum Columns: String, ColumnExpression {
        case id, title, description, completed, priority
        case completeBy = "complete_by"
        case createdOn = "created_on"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
        case sortOrder = "sort_order"
        case hlcJSON = "hlc_json"
        case deletedAt = "deleted_at"
        case fieldClocksJSON = "field_clocks_json"
        case versionJSON = "version_json"
    }

    public init(row: Row) {
        id = UUID(uuidString: row[Columns.id]) ?? UUID()
        title = row[Columns.title]
        description = row[Columns.description]
        completed = row[Columns.completed]
        priority = TodoPriority(rawValue: row[Columns.priority]) ?? .medium
        completeBy = row[Columns.completeBy]
        createdOn = row[Columns.createdOn]
        updatedAt = row[Columns.updatedAt]
        completedAt = row[Columns.completedAt]
        sortOrder = row[Columns.sortOrder]
        if let hlcStr: String = row[Columns.hlcJSON], !hlcStr.isEmpty,
           let decoded = try? SyncJSON.decode(HybridLogicalClock.self, from: hlcStr) {
            hlc = decoded
        } else {
            hlc = SyncPlaceholder.draftHLC
        }
        deletedAt = row[Columns.deletedAt]
        if let fcStr: String = row[Columns.fieldClocksJSON], !fcStr.isEmpty,
           let fc = try? SyncJSON.decode(FieldClockMap.self, from: fcStr) {
            fieldClocks = fc
        } else {
            fieldClocks = .empty
        }
        if let vStr: String = row[Columns.versionJSON], !vStr.isEmpty,
           let vv = try? SyncJSON.decode(VersionVector.self, from: vStr) {
            version = vv
        } else {
            version = VersionVector()
        }
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.title] = title
        container[Columns.description] = description
        container[Columns.completed] = completed
        container[Columns.priority] = priority.rawValue
        container[Columns.completeBy] = completeBy
        container[Columns.createdOn] = createdOn
        container[Columns.updatedAt] = updatedAt
        container[Columns.completedAt] = completedAt
        container[Columns.sortOrder] = sortOrder
        container[Columns.hlcJSON] = (try? SyncJSON.encode(hlc)) ?? "{}"
        container[Columns.deletedAt] = deletedAt
        container[Columns.fieldClocksJSON] = (try? SyncJSON.encode(fieldClocks)) ?? "{}"
        container[Columns.versionJSON] = (try? SyncJSON.encode(version)) ?? "{}"
    }
}
