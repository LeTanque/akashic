import Foundation
import GRDB
import SwiftUI

enum NoteListSort: String, CaseIterable, Identifiable {
    case updatedNewest = "Updated"
    case titleAZ = "Title"
    case tagAZ = "Tag"

    var id: String { rawValue }
}

@MainActor
final class NoteStore: ObservableObject {
    @Published private(set) var notes: [NoteItem] = []
    @Published var selectedNoteID: UUID?
    @Published private(set) var completionCelebrationID: UUID?
    @Published private(set) var deletionCelebrationID: UUID?
    @Published private(set) var revealNoteInListID: UUID?

    private let db: DatabaseQueue

    init() {
        db = (try? TodoDatabase.open()) ?? {
            fatalError("Failed to open Akashic database")
        }()
        refresh()
    }

    init(db: DatabaseQueue) {
        self.db = db
        refresh()
    }

    static func isolatedForTesting() throws -> NoteStore {
        try NoteStore(db: TodoDatabase.openInMemory())
    }

    var selectedNote: NoteItem? {
        guard let id = selectedNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    func refresh() {
        notes = (try? db.read { db in
            try Self.loadNotesWithTags(db)
        }) ?? []
        sortNotesInMemory()
    }

    func beginNewNoteDraft() {
        selectedNoteID = nil
    }

    @discardableResult
    func insertSavedNote(from draft: NoteItem) -> NoteItem {
        var item = draft
        item.tags = NoteTagNormalization.normalizeTags(item.tags)
        item.updatedAt = Date()
        try? db.write { db in
            try item.save(db)
            try Self.syncNoteTagLinks(noteID: item.id, tags: item.tags, db: db)
        }
        refresh()
        return notes.first { $0.id == item.id } ?? item
    }

    func update(_ item: NoteItem) {
        var copy = item
        copy.tags = NoteTagNormalization.normalizeTags(copy.tags)
        copy.updatedAt = Date()
        try? db.write { db in
            try copy.save(db)
            try Self.syncNoteTagLinks(noteID: copy.id, tags: copy.tags, db: db)
        }
        refresh()
    }

    func delete(_ item: NoteItem) {
        _ = try? db.write { db in
            try item.delete(db)
        }
        if selectedNoteID == item.id {
            selectedNoteID = nil
        }
        refresh()
        deletionCelebrationID = UUID()
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        guard let item = notes.first(where: { $0.id == id }) else { return false }
        delete(item)
        return true
    }

    func triggerBreathingCelebration() {
        completionCelebrationID = UUID()
    }

    func revealNoteInList(_ id: UUID) {
        revealNoteInListID = id
    }

    /// All tag definitions (global palette metadata).
    func allTagDefinitions() -> [AkashicTag] {
        (try? db.read { db in
            try TagRecord.fetchAll(db).map(\.akashicTag)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }) ?? []
    }

    func tagsUsedInNotes() -> [AkashicTag] {
        let keys = Set(notes.flatMap { $0.tags.map(\.nameKey) })
        return allTagDefinitions().filter { keys.contains($0.nameKey) }
    }

    @discardableResult
    func setTagColor(name: String, color: AkashicTagColor) -> AkashicTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = trimmed.lowercased()
        try? db.write { db in
            if var existing = try TagRecord.fetchOne(db, key: key) {
                existing.color = color.rawValue
                try existing.update(db)
            } else {
                try TagRecord(nameKey: key, displayName: trimmed, color: color.rawValue).insert(db)
            }
        }
        refresh()
        return allTagDefinitions().first { $0.nameKey == key }
    }

    func filteredNotes(tag: AkashicTag?, sort: NoteListSort) -> [NoteItem] {
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

    func note(id: UUID) -> NoteItem? {
        notes.first { $0.id == id }
    }

    private func sortNotesInMemory() {
        notes.sort { $0.updatedAt > $1.updatedAt }
    }

    private static func loadNotesWithTags(_ db: Database) throws -> [NoteItem] {
        var items = try NoteItem.fetchAll(db)
        let rows = try Row.fetchAll(db, sql: """
            SELECT nt.note_id, t.display_name, t.color, t.name_key
            FROM \(NoteTagLinkRow.databaseTableName) nt
            JOIN \(TagRecord.databaseTableName) t ON t.name_key = nt.tag_name_key
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

    private static func syncNoteTagLinks(noteID: UUID, tags: [AkashicTag], db: Database) throws {
        let normalized = NoteTagNormalization.normalizeTags(tags)
        for tag in normalized {
            try upsertTagRecord(tag, db: db)
        }
        try db.execute(
            sql: "DELETE FROM \(NoteTagLinkRow.databaseTableName) WHERE note_id = ?",
            arguments: [noteID.uuidString]
        )
        for tag in normalized {
            try db.execute(
                sql: """
                INSERT INTO \(NoteTagLinkRow.databaseTableName) (note_id, tag_name_key)
                VALUES (?, ?)
                """,
                arguments: [noteID.uuidString, tag.nameKey]
            )
        }
    }

    private static func upsertTagRecord(_ tag: AkashicTag, db: Database) throws {
        let key = tag.nameKey
        if try TagRecord.fetchOne(db, key: key) == nil {
            try TagRecord(
                nameKey: key,
                displayName: tag.name,
                color: tag.color.rawValue
            ).insert(db)
        }
    }
}
