import Combine
import Foundation
import GRDB

public enum NoteListSort: String, CaseIterable, Identifiable, Sendable {
    case updatedNewest = "Updated"
    case titleAZ = "Title"
    case tagAZ = "Tag"

    public var id: String { rawValue }
}

@MainActor
public final class NoteStore: ObservableObject {
    @Published public private(set) var notes: [NoteItem] = []
    @Published public var selectedNoteID: UUID?
    @Published public private(set) var completionCelebrationID: UUID?
    @Published public private(set) var deletionCelebrationID: UUID?
    @Published public private(set) var revealNoteInListID: UUID?

    private let db: DatabaseQueue
    private var installation: InstallationContext

    public init(db: DatabaseQueue) {
        self.db = db
        installation = try! db.write { try InstallationContext.loadOrCreate(in: $0) }
        refresh()
    }

    public static func isolatedForTesting() throws -> NoteStore {
        try NoteStore(db: TodoDatabase.openInMemory())
    }

    public var selectedNote: NoteItem? {
        guard let id = selectedNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    public func refresh() {
        notes = (try? db.read { db in
            try Self.loadNotesWithTags(db)
        }) ?? []
        sortNotesInMemory()
    }

    public func beginNewNoteDraft() {
        selectedNoteID = nil
    }

    @discardableResult
    public func insertSavedNote(from draft: NoteItem) -> NoteItem {
        try! db.write { db in
            var item = draft
            item.tags = NoteTagNormalization.normalizeTags(item.tags)
            let now = Date()
            let clock = self.installation.tick()
            item.createdAt = now
            item.updatedAt = now
            item.hlc = clock
            item.deletedAt = nil
            item.fieldClocks = FieldClockMap(fields: [
                "title": clock,
                "body": clock,
                "tags": clock,
            ])
            item.version = VersionVector(map: [self.installation.deviceId: clock])
            try item.insert(db)
            try self.syncNoteTagLinks(noteID: item.id, tags: item.tags, db: db, clock: clock)
            try self.appendChangeLog(
                entity: .note,
                recordID: item.id.uuidString,
                fields: ["created": "1"],
                hlc: clock,
                db: db
            )
        }
        refresh()
        return notes.first { $0.id == draft.id } ?? draft
    }

    public func update(_ item: NoteItem) {
        try! db.write { db in
            try self.persistNoteUpdate(item, db: db)
        }
        refresh()
    }

    public func delete(_ item: NoteItem) {
        _ = try? db.write { db in
            try self.softDeleteNote(item.id, db: db)
        }
        if selectedNoteID == item.id {
            selectedNoteID = nil
        }
        refresh()
        deletionCelebrationID = UUID()
    }

    @discardableResult
    public func delete(id: UUID) -> Bool {
        guard let item = notes.first(where: { $0.id == id }) else { return false }
        delete(item)
        return true
    }

    public func triggerBreathingCelebration() {
        completionCelebrationID = UUID()
    }

    public func revealNoteInList(_ id: UUID) {
        revealNoteInListID = id
    }

    /// All tag definitions (global palette metadata).
    public func allTagDefinitions() -> [AkashicTag] {
        (try? db.read { db in
            try TagRecord
                .filter(Column("deleted_at") == nil)
                .fetchAll(db)
                .map(\.akashicTag)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }) ?? []
    }

    public func tagsUsedInNotes() -> [AkashicTag] {
        let keys = Set(notes.flatMap { $0.tags.map(\.nameKey) })
        return allTagDefinitions().filter { keys.contains($0.nameKey) }
    }

    public enum SetTagColorOutcome: Equatable, Sendable {
        case updated(AkashicTag)
        case notFound
        case invalidName
    }

    @discardableResult
    public func setTagColor(name: String, color: AkashicTagColor) -> SetTagColorOutcome {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalidName }
        let key = trimmed.lowercased()
        let updated: Bool = (try? db.write { db in
            guard var existing = try TagRecord.fetchOne(db, key: key) else { return false }
            let clock = self.installation.tick()
            if existing.deletedAt != nil {
                existing.deletedAt = nil
                existing.fieldClocks.removeField("deleted_at")
            }
            existing.color = color.rawValue
            existing.hlc = clock
            existing.fieldClocks["color"] = clock
            existing.version.set(clock)
            try existing.update(db)
            try self.appendChangeLog(
                entity: .tag,
                recordID: existing.syncId.uuidString,
                fields: ["color": color.rawValue],
                hlc: clock,
                db: db
            )
            return true
        }) ?? false
        guard updated else { return .notFound }
        refresh()
        guard let tag = allTagDefinitions().first(where: { $0.nameKey == key }) else {
            return .notFound
        }
        return .updated(tag)
    }

    public func filteredNotes(tag: AkashicTag?, sort: NoteListSort) -> [NoteItem] {
        var list = notes
        if let tag {
            list = list.filter { note in
                note.tags.contains { $0.nameKey == tag.nameKey }
            }
        }
        switch sort {
        case .updatedNewest:
            list.sort { $0.updatedAt > $1.updatedAt }
        case .titleAZ:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .tagAZ:
            list.sort { lhs, rhs in
                let lt = lhs.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.first?.name ?? ""
                let rt = rhs.tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.first?.name ?? ""
                let tagCompare = lt.localizedCaseInsensitiveCompare(rt)
                if tagCompare != .orderedSame { return tagCompare == .orderedAscending }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        return list
    }

    public func note(id: UUID) -> NoteItem? {
        notes.first { $0.id == id }
    }

    private func sortNotesInMemory() {
        notes.sort { $0.updatedAt > $1.updatedAt }
    }

    private static func loadNotesWithTags(_ db: Database) throws -> [NoteItem] {
        var items = try NoteItem
            .filter(Column("deleted_at") == nil)
            .fetchAll(db)
        let rows = try Row.fetchAll(db, sql: """
            SELECT nt.note_id, t.display_name, t.color, t.name_key
            FROM \(NoteTagLinkRow.databaseTableName) nt
            JOIN \(TagRecord.databaseTableName) t ON t.name_key = nt.tag_name_key
            WHERE nt.deleted_at IS NULL AND t.deleted_at IS NULL
            ORDER BY t.display_name COLLATE NOCASE ASC
            """)
        var tagsByNote: [UUID: [AkashicTag]] = [:]
        for row in rows {
            let idString: String = row["note_id"]
            let displayName: String = row["display_name"]
            let color: String = row["color"]
            guard let id = UUID(uuidString: idString) else { continue }
            let tag = AkashicTag(name: displayName, color: AkashicTagColor.validated(color))
            tagsByNote[id, default: []].append(tag)
        }
        for index in items.indices {
            items[index].tags = tagsByNote[items[index].id] ?? []
        }
        return items
    }

    private func syncNoteTagLinks(noteID: UUID, tags: [AkashicTag], db: Database, clock: HybridLogicalClock) throws {
        let normalized = NoteTagNormalization.normalizeTags(tags)
        for tag in normalized {
            try upsertTagRecord(tag, db: db, clock: clock)
        }

        let desired = Set(normalized.map(\.nameKey))
        let allRows = try NoteTagLinkRow.fetchAll(
            db,
            sql: "SELECT * FROM \(NoteTagLinkRow.databaseTableName) WHERE note_id = ?",
            arguments: [noteID.uuidString]
        )

        for row in allRows {
            let isLive = row.deletedAt == nil
            let want = desired.contains(row.tagNameKey)
            if isLive && !want {
                try softDeleteNoteTagLink(row, db: db, clock: clock)
            }
        }

        for key in desired {
            let rowsForKey = allRows.filter { $0.tagNameKey == key }
            if rowsForKey.contains(where: { $0.deletedAt == nil }) {
                continue
            }
            if let tomb = rowsForKey.first(where: { $0.deletedAt != nil }) {
                var resurrected = tomb
                resurrected.deletedAt = nil
                resurrected.hlc = clock
                resurrected.fieldClocks = FieldClockMap(fields: ["link": clock])
                resurrected.fieldClocks.removeField("deleted_at")
                resurrected.version.set(clock)
                try resurrected.save(db)
                try appendChangeLog(
                    entity: .noteTag,
                    recordID: "\(noteID.uuidString)|\(key)",
                    fields: ["link": "add"],
                    hlc: clock,
                    db: db
                )
                continue
            }
            let link = NoteTagLinkRow(
                noteID: noteID,
                tagNameKey: key,
                hlc: clock,
                fieldClocks: FieldClockMap(fields: ["link": clock]),
                version: VersionVector(map: [installation.deviceId: clock]),
                deletedAt: nil
            )
            try link.insert(db)
            try appendChangeLog(
                entity: .noteTag,
                recordID: "\(noteID.uuidString)|\(key)",
                fields: ["link": "add"],
                hlc: clock,
                db: db
            )
        }
    }

    private func softDeleteNoteTagLink(_ row: NoteTagLinkRow, db: Database, clock: HybridLogicalClock) throws {
        var copy = row
        copy.deletedAt = Date()
        copy.hlc = clock
        copy.fieldClocks["deleted_at"] = clock
        copy.version.set(clock)
        try copy.update(db)
        try appendChangeLog(
            entity: .noteTag,
            recordID: "\(row.noteID.uuidString)|\(row.tagNameKey)",
            fields: ["link": "remove"],
            hlc: clock,
            db: db
        )
    }

    private func upsertTagRecord(_ tag: AkashicTag, db: Database, clock: HybridLogicalClock) throws {
        let key = tag.nameKey
        guard var existing = try TagRecord.fetchOne(db, key: key) else {
            let record = TagRecord(
                syncId: UUID(),
                nameKey: key,
                displayName: tag.name,
                color: tag.color.rawValue,
                hlc: clock,
                fieldClocks: FieldClockMap(fields: [
                    "display_name": clock,
                    "color": clock,
                ]),
                version: VersionVector(map: [installation.deviceId: clock]),
                deletedAt: nil
            )
            try record.insert(db)
            try appendChangeLog(
                entity: .tag,
                recordID: record.syncId.uuidString,
                fields: ["created": tag.name],
                hlc: clock,
                db: db
            )
            return
        }
        if existing.deletedAt != nil {
            existing.deletedAt = nil
            existing.fieldClocks.removeField("deleted_at")
        }
        if existing.displayName != tag.name {
            existing.displayName = tag.name
            existing.fieldClocks["display_name"] = clock
        }
        if existing.color != tag.color.rawValue {
            existing.color = tag.color.rawValue
            existing.fieldClocks["color"] = clock
        }
        existing.hlc = clock
        existing.version.set(clock)
        try existing.update(db)
    }

    private func persistNoteUpdate(_ item: NoteItem, db: Database) throws {
        let before = try NoteItem.fetchOne(db, key: item.id.uuidString)
        var copy = item
        copy.tags = NoteTagNormalization.normalizeTags(copy.tags)
        copy.updatedAt = Date()
        let clock = installation.tick()
        copy.hlc = clock
        var changed = diffNoteKeys(before: before, after: copy)
        let tagDiffers: Bool = {
            guard let before else { return !copy.tags.isEmpty }
            return NoteTagNormalization.tagNameSet(before.tags) != NoteTagNormalization.tagNameSet(copy.tags)
        }()
        if tagDiffers {
            changed.insert("tags")
        }
        for k in changed {
            copy.fieldClocks[k] = clock
        }
        copy.version.set(clock)
        try copy.save(db)
        try syncNoteTagLinks(noteID: copy.id, tags: copy.tags, db: db, clock: clock)
        try appendChangeLog(
            entity: .note,
            recordID: copy.id.uuidString,
            fields: fieldChangeMap(for: changed, clock: clock),
            hlc: clock,
            db: db
        )
    }

    private func softDeleteNote(_ id: UUID, db: Database) throws {
        guard var row = try NoteItem.fetchOne(db, key: id.uuidString) else { return }
        let clock = installation.tick()
        row.deletedAt = Date()
        row.hlc = clock
        row.fieldClocks["deleted_at"] = clock
        row.version.set(clock)
        try row.save(db)
        try appendChangeLog(
            entity: .note,
            recordID: id.uuidString,
            fields: ["deleted_at": "\(clock.wallMillis)"],
            hlc: clock,
            db: db
        )

        let links = try NoteTagLinkRow.fetchAll(
            db,
            sql: "SELECT * FROM \(NoteTagLinkRow.databaseTableName) WHERE note_id = ? AND deleted_at IS NULL",
            arguments: [id.uuidString]
        )
        for link in links {
            try softDeleteNoteTagLink(link, db: db, clock: clock)
        }
    }

    private func diffNoteKeys(before: NoteItem?, after: NoteItem) -> Set<String> {
        guard let before else {
            return ["title", "body", "tags"]
        }
        var keys = Set<String>()
        if before.title != after.title { keys.insert("title") }
        if before.body != after.body { keys.insert("body") }
        let bTags = NoteTagNormalization.tagNameSet(before.tags)
        let aTags = NoteTagNormalization.tagNameSet(after.tags)
        if bTags != aTags { keys.insert("tags") }
        return keys
    }

    private func fieldChangeMap(for keys: Set<String>, clock: HybridLogicalClock) -> [String: String] {
        var m: [String: String] = [:]
        for k in keys.sorted() {
            m[k] = "\(clock.wallMillis)-\(clock.counter)"
        }
        return m
    }

    private func appendChangeLog(entity: SyncEntity, recordID: String, fields: [String: String], hlc: HybridLogicalClock, db: Database) throws {
        guard !fields.isEmpty else { return }
        let entry = ChangeLogEntry(
            recordID: recordID,
            entity: entity,
            fieldChanges: fields,
            hlc: hlc,
            deviceID: installation.deviceId
        )
        try entry.insert(db)
    }
}
