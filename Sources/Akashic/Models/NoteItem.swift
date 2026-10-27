import Foundation
import GRDB

struct NoteItem: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var tags: [AkashicTag]

    static func new(
        title: String = "",
        body: String = "",
        tags: [AkashicTag] = []
    ) -> NoteItem {
        let now = Date()
        return NoteItem(
            id: UUID(),
            title: title,
            body: body,
            createdAt: now,
            updatedAt: now,
            tags: NoteTagNormalization.normalizeTags(tags)
        )
    }

    func hasSameEditableContent(as other: NoteItem) -> Bool {
        id == other.id
            && title == other.title
            && body == other.body
            && NoteTagNormalization.tagNameSet(tags) == NoteTagNormalization.tagNameSet(other.tags)
    }
}

extension NoteItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "notes"

    enum Columns: String, ColumnExpression {
        case id, title, body
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(row: Row) {
        id = UUID(uuidString: row[Columns.id]) ?? UUID()
        title = row[Columns.title]
        body = row[Columns.body]
        createdAt = row[Columns.createdAt]
        updatedAt = row[Columns.updatedAt]
        tags = []
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.title] = title
        container[Columns.body] = body
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

struct TagRecord: FetchableRecord, PersistableRecord, TableRecord, Equatable {
    static let databaseTableName = "tags"

    enum Columns: String, ColumnExpression {
        case nameKey = "name_key"
        case displayName = "display_name"
        case color
    }

    var nameKey: String
    var displayName: String
    var color: String

    var akashicTag: AkashicTag {
        AkashicTag(name: displayName, color: AkashicTagColor.validated(color))
    }
}

struct NoteTagLinkRow: FetchableRecord, PersistableRecord {
    static let databaseTableName = "note_tags"

    enum Columns: String, ColumnExpression {
        case noteID = "note_id"
        case tagNameKey = "tag_name_key"
    }

    var noteID: UUID
    var tagNameKey: String
}
