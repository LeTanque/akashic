import Foundation
import GRDB

public struct NoteItem: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [AkashicTag]

    public var hlc: HybridLogicalClock
    public var deletedAt: Date?
    public var fieldClocks: FieldClockMap
    public var version: VersionVector

    public static func new(
        title: String = "",
        body: String = "",
        tags: [AkashicTag] = [],
        deviceId: UUID,
        clock: HybridLogicalClock
    ) -> NoteItem {
        let now = Date()
        let vv = VersionVector(map: [deviceId: clock])
        let fc = FieldClockMap(fields: [
            "title": clock,
            "body": clock,
            "tags": clock,
        ])
        return NoteItem(
            id: UUID(),
            title: title,
            body: body,
            createdAt: now,
            updatedAt: now,
            tags: NoteTagNormalization.normalizeTags(tags),
            hlc: clock,
            deletedAt: nil,
            fieldClocks: fc,
            version: vv
        )
    }

    /// In-memory draft before first save.
    public static func unsavedDraft(
        title: String = "",
        body: String = "",
        tags: [AkashicTag] = []
    ) -> NoteItem {
        let now = Date()
        let ph = SyncPlaceholder.draftHLC
        return NoteItem(
            id: UUID(),
            title: title,
            body: body,
            createdAt: now,
            updatedAt: now,
            tags: NoteTagNormalization.normalizeTags(tags),
            hlc: ph,
            deletedAt: nil,
            fieldClocks: .empty,
            version: VersionVector()
        )
    }

    public func hasSameEditableContent(as other: NoteItem) -> Bool {
        id == other.id
            && title == other.title
            && body == other.body
            && NoteTagNormalization.tagNameSet(tags) == NoteTagNormalization.tagNameSet(other.tags)
    }

    public var isTombstoned: Bool { deletedAt != nil }
}

extension NoteItem: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "notes"

    public enum Columns: String, ColumnExpression {
        case id, title, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case hlcJSON = "hlc_json"
        case deletedAt = "deleted_at"
        case fieldClocksJSON = "field_clocks_json"
        case versionJSON = "version_json"
    }

    public init(row: Row) {
        id = UUID(uuidString: row[Columns.id]) ?? UUID()
        title = row[Columns.title]
        body = row[Columns.body]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
        tags = []
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
        container[Columns.body] = body
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
        container[Columns.hlcJSON] = (try? SyncJSON.encode(hlc)) ?? "{}"
        container[Columns.deletedAt] = deletedAt
        container[Columns.fieldClocksJSON] = (try? SyncJSON.encode(fieldClocks)) ?? "{}"
        container[Columns.versionJSON] = (try? SyncJSON.encode(version)) ?? "{}"
    }
}

public struct TagRecord: FetchableRecord, PersistableRecord, TableRecord, Equatable, Sendable {
    public static let databaseTableName = "tags"

    public enum Columns: String, ColumnExpression {
        case nameKey = "name_key"
        case displayName = "display_name"
        case color
        case syncID = "sync_id"
        case hlcJSON = "hlc_json"
        case deletedAt = "deleted_at"
        case fieldClocksJSON = "field_clocks_json"
        case versionJSON = "version_json"
    }

    /// Stable identity for sync (also used in API “id” long-term).
    public var syncId: UUID
    public var nameKey: String
    public var displayName: String
    public var color: String

    public var hlc: HybridLogicalClock
    public var deletedAt: Date?
    public var fieldClocks: FieldClockMap
    public var version: VersionVector

    public init(syncId: UUID, nameKey: String, displayName: String, color: String, hlc: HybridLogicalClock, fieldClocks: FieldClockMap, version: VersionVector, deletedAt: Date? = nil) {
        self.syncId = syncId
        self.nameKey = nameKey
        self.displayName = displayName
        self.color = color
        self.hlc = hlc
        self.deletedAt = deletedAt
        self.fieldClocks = fieldClocks
        self.version = version
    }

    public init(row: Row) {
        nameKey = row[Columns.nameKey]
        displayName = row[Columns.displayName]
        color = row[Columns.color]
        if let sid: String = row[Columns.syncID],
           !sid.isEmpty,
           let u = UUID(uuidString: sid) {
            syncId = u
        } else {
            syncId = UUID()
        }
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
        container[Columns.nameKey] = nameKey
        container[Columns.displayName] = displayName
        container[Columns.color] = color
        container[Columns.syncID] = syncId.uuidString
        container[Columns.hlcJSON] = (try? SyncJSON.encode(hlc)) ?? "{}"
        container[Columns.deletedAt] = deletedAt
        container[Columns.fieldClocksJSON] = (try? SyncJSON.encode(fieldClocks)) ?? "{}"
        container[Columns.versionJSON] = (try? SyncJSON.encode(version)) ?? "{}"
    }

    public var akashicTag: AkashicTag {
        AkashicTag(name: displayName, color: AkashicTagColor.validated(color))
    }

    /// Prefer persisted sync id; if the column was missing or empty, assign a new stable id.
    public func resolvedSyncId() -> UUID {
        syncId
    }
}

public struct NoteTagLinkRow: FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "note_tags"

    public enum Columns: String, ColumnExpression {
        case noteID = "note_id"
        case tagNameKey = "tag_name_key"
        case hlcJSON = "hlc_json"
        case deletedAt = "deleted_at"
        case fieldClocksJSON = "field_clocks_json"
        case versionJSON = "version_json"
    }

    public var noteID: UUID
    public var tagNameKey: String

    public var hlc: HybridLogicalClock
    public var deletedAt: Date?
    public var fieldClocks: FieldClockMap
    public var version: VersionVector

    public init(noteID: UUID, tagNameKey: String, hlc: HybridLogicalClock, fieldClocks: FieldClockMap, version: VersionVector, deletedAt: Date? = nil) {
        self.noteID = noteID
        self.tagNameKey = tagNameKey
        self.hlc = hlc
        self.deletedAt = deletedAt
        self.fieldClocks = fieldClocks
        self.version = version
    }

    public init(row: Row) {
        noteID = UUID(uuidString: row[Columns.noteID]) ?? UUID()
        tagNameKey = row[Columns.tagNameKey]
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
        container[Columns.noteID] = noteID.uuidString
        container[Columns.tagNameKey] = tagNameKey
        container[Columns.hlcJSON] = (try? SyncJSON.encode(hlc)) ?? "{}"
        container[Columns.deletedAt] = deletedAt
        container[Columns.fieldClocksJSON] = (try? SyncJSON.encode(fieldClocks)) ?? "{}"
        container[Columns.versionJSON] = (try? SyncJSON.encode(version)) ?? "{}"
    }

    public var isTombstoned: Bool { deletedAt != nil }
}
