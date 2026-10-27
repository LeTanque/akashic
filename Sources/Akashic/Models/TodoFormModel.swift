import Foundation

enum UnsavedChangesGuardDecision: Equatable {
    case allow
    case needsConfirmation
}

enum UnsavedChangesChoice: Equatable {
    case save
    case discard
    case cancel
}

enum TodoFormSaveResult: Equatable {
    case created(UUID)
    case updated(UUID)
}

/// In-memory todo form state: blank draft, new-with-input, or editing a saved todo.
struct TodoFormModel: Equatable {
    var draft: TodoItem
    private(set) var savedBaseline: TodoItem?
    var hasCompleteBy: Bool

    static func blank() -> TodoFormModel {
        TodoFormModel(draft: blankItem(), savedBaseline: nil, hasCompleteBy: false)
    }

    static func blankItem() -> TodoItem {
        TodoItem.new(title: "", description: "", priority: .medium)
    }

    var isNew: Bool { savedBaseline == nil }

    var isDirty: Bool {
        if isNew {
            return Self.hasContentBeyondBlank(draft)
        }
        guard let saved = savedBaseline else { return false }
        return !draft.hasSameEditableContent(as: saved) || draft.completed != saved.completed
    }

    var canSave: Bool {
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if isNew { return true }
        return isDirty
    }

    var canDiscard: Bool {
        !isNew && isDirty
    }

    mutating func load(_ todo: TodoItem) {
        draft = todo
        savedBaseline = todo
        hasCompleteBy = todo.completeBy != nil
    }

    mutating func reset() {
        self = .blank()
    }

    mutating func discard() {
        if let saved = savedBaseline {
            draft = saved
            hasCompleteBy = saved.completeBy != nil
        } else {
            reset()
        }
    }

    /// Keeps in-progress form edits while applying an immediate completion write from the store.
    mutating func syncSavedCompletion(from item: TodoItem) {
        guard var baseline = savedBaseline, baseline.id == item.id else { return }
        draft.completed = item.completed
        draft.completedAt = item.completedAt
        draft.updatedAt = item.updatedAt
        baseline.completed = item.completed
        baseline.completedAt = item.completedAt
        baseline.updatedAt = item.updatedAt
        savedBaseline = baseline
    }

    @discardableResult
    mutating func save(into store: TodoStore) -> TodoFormSaveResult? {
        guard canSave else { return nil }
        if isNew {
            let item = store.insertSavedTodo(from: draft)
            reset()
            return .created(item.id)
        }
        guard let baseline = savedBaseline else { return nil }
        var toSave = draft
        toSave.id = baseline.id
        toSave.createdOn = baseline.createdOn
        toSave.sortOrder = baseline.sortOrder
        toSave.completedAt = draft.completed ? (draft.completedAt ?? baseline.completedAt ?? Date()) : nil
        store.update(toSave)
        if let updated = store.todos.first(where: { $0.id == baseline.id }) {
            load(updated)
        }
        return .updated(baseline.id)
    }

    static func unsavedChangesGuard(isDirty: Bool) -> UnsavedChangesGuardDecision {
        isDirty ? .needsConfirmation : .allow
    }

    static func hasContentBeyondBlank(_ item: TodoItem) -> Bool {
        let blank = blankItem()
        if !item.title.isEmpty { return true }
        if !item.description.isEmpty { return true }
        if item.priority != blank.priority { return true }
        if item.completeBy != nil { return true }
        if item.completed { return true }
        return false
    }
}
