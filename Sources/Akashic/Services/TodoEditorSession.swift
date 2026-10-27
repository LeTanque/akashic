import Foundation
import SwiftUI

@MainActor
final class TodoEditorSession: ObservableObject {
    @Published private(set) var form = TodoFormModel.blank()
    @Published var requestTitleFocus: UUID?
    private var isHandlingNavigation = false

    func mutateForm(_ update: (inout TodoFormModel) -> Void) {
        update(&form)
        objectWillChange.send()
    }

    func syncToSelection(store: TodoStore, selectedID: UUID?) {
        guard !isHandlingNavigation else { return }
        if let id = selectedID, let todo = store.todos.first(where: { $0.id == id }) {
            form.load(todo)
        } else if selectedID == nil {
            form.reset()
        }
    }

    @discardableResult
    func save(store: TodoStore) -> Bool {
        guard let result = form.save(into: store) else { return false }
        switch result {
        case .created(let id):
            store.selectedTodoID = nil
            store.revealTodoInList(id)
        case .updated(let id):
            store.selectedTodoID = id
        }
        if CompletionCelebration.shouldCelebrateSuccessfulSave(saveResult: result) {
            store.triggerBreathingCelebration()
        }
        return true
    }

    @discardableResult
    func selectTodo(_ todo: TodoItem, store: TodoStore) -> Bool {
        guard resolveUnsavedChanges(store: store) else { return false }
        isHandlingNavigation = true
        store.selectedTodoID = todo.id
        form.load(todo)
        isHandlingNavigation = false
        return true
    }

    @discardableResult
    func beginNewTodo(store: TodoStore) -> Bool {
        guard resolveUnsavedChanges(store: store) else { return false }
        isHandlingNavigation = true
        store.selectedTodoID = nil
        form.reset()
        requestTitleFocus = UUID()
        isHandlingNavigation = false
        return true
    }

    @discardableResult
    func resolveUnsavedChanges(store: TodoStore) -> Bool {
        switch TodoFormModel.unsavedChangesGuard(isDirty: form.isDirty) {
        case .allow:
            return true
        case .needsConfirmation:
            switch AkashicUnsavedChangesConfirmations.confirm() {
            case .save:
                guard save(store: store) else { return false }
                return true
            case .discard:
                form.discard()
                return true
            case .cancel:
                return false
            }
        }
    }

    @discardableResult
    func confirmQuit(store: TodoStore) -> Bool {
        resolveUnsavedChanges(store: store)
    }

    func applyCompletionToggle(for id: UUID, store: TodoStore) {
        store.toggleCompletion(for: id)
        if let updated = store.todos.first(where: { $0.id == id }) {
            syncCompletionFromStore(updated)
        }
    }

    func syncCompletionFromStore(_ item: TodoItem) {
        mutateForm { $0.syncSavedCompletion(from: item) }
    }

    func toggleDraftCompletion() {
        form.draft.completed.toggle()
        if form.draft.completed {
            form.draft.completedAt = Date()
        } else {
            form.draft.completedAt = nil
        }
    }
}
