import Foundation

enum NoteFormSaveResult: Equatable {
    case created(UUID)
    case updated(UUID)
}

struct NoteFormModel: Equatable {
    var draft: NoteItem
    private(set) var savedBaseline: NoteItem?
    var tagInput: String

    static func blank() -> NoteFormModel {
        NoteFormModel(draft: blankItem(), savedBaseline: nil, tagInput: "")
    }

    static func blankItem() -> NoteItem {
        NoteItem.new(title: "", body: "", tags: [])
    }

    var isNew: Bool { savedBaseline == nil }

    var isDirty: Bool {
        if isNew {
            return Self.hasContentBeyondBlank(draft)
        }
        guard let saved = savedBaseline else { return false }
        return !draft.hasSameEditableContent(as: saved)
    }

    var canSave: Bool {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if isNew { return true }
        return isDirty
    }

    var canDiscard: Bool {
        !isNew && isDirty
    }

    mutating func load(_ note: NoteItem) {
        draft = note
        savedBaseline = note
        tagInput = ""
    }

    /// Refresh tag colors from store without marking dirty (after global recolor).
    mutating func refreshTagColors(from note: NoteItem) {
        guard draft.id == note.id else { return }
        draft.tags = note.tags
        savedBaseline?.tags = note.tags
    }

    mutating func reset() {
        self = .blank()
    }

    mutating func discard() {
        if let saved = savedBaseline {
            draft = saved
            tagInput = ""
        } else {
            reset()
        }
    }

    mutating func commitTagsFromInput() {
        let parsed = NoteTagNormalization.parseInput(tagInput)
        guard !parsed.isEmpty else { return }
        let newTags = parsed.map { AkashicTag(name: $0, color: .defaultForNewTag) }
        draft.tags = NoteTagNormalization.normalizeTags(draft.tags + newTags)
        tagInput = ""
    }

    mutating func removeTag(_ tag: AkashicTag) {
        draft.tags.removeAll { $0.nameKey == tag.nameKey }
    }

    @MainActor
    @discardableResult
    mutating func save(into store: NoteStore) -> NoteFormSaveResult? {
        commitTagsFromInput()
        guard canSave else { return nil }
        if isNew {
            let item = store.insertSavedNote(from: draft)
            reset()
            return .created(item.id)
        }
        guard let baseline = savedBaseline else { return nil }
        var toSave = draft
        toSave.id = baseline.id
        toSave.createdAt = baseline.createdAt
        store.update(toSave)
        if let updated = store.notes.first(where: { $0.id == baseline.id }) {
            load(updated)
        }
        return .updated(baseline.id)
    }

    static func unsavedChangesGuard(isDirty: Bool) -> UnsavedChangesGuardDecision {
        isDirty ? .needsConfirmation : .allow
    }

    static func hasContentBeyondBlank(_ item: NoteItem) -> Bool {
        if !item.title.isEmpty { return true }
        if !item.body.isEmpty { return true }
        if !item.tags.isEmpty { return true }
        return false
    }
}
