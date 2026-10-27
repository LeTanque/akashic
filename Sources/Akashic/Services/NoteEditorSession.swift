import Foundation
import SwiftUI

@MainActor
final class NoteEditorSession: ObservableObject {
    @Published private(set) var form = NoteFormModel.blank()
    @Published var requestTitleFocus: UUID?
    private var isHandlingNavigation = false
    private let presentUnsavedChanges: @MainActor (_ itemDisplayName: String) -> UnsavedChangesChoice

    init(
        presentUnsavedChanges: @escaping @MainActor (_ itemDisplayName: String) -> UnsavedChangesChoice =
            UnsavedChangesAlertPresenter.present
    ) {
        self.presentUnsavedChanges = presentUnsavedChanges
    }

    func mutateForm(_ update: (inout NoteFormModel) -> Void) {
        update(&form)
        objectWillChange.send()
    }

    func syncToSelection(store: NoteStore, selectedID: UUID?) {
        guard !isHandlingNavigation else { return }
        if let id = selectedID, let note = store.notes.first(where: { $0.id == id }) {
            form.load(note)
        } else if selectedID == nil {
            form.reset()
        }
    }

    @discardableResult
    func save(store: NoteStore) -> Bool {
        guard let result = form.save(into: store) else { return false }
        switch result {
        case .created(let id):
            store.selectedNoteID = nil
            store.revealNoteInList(id)
        case .updated(let id):
            store.selectedNoteID = id
        }
        if CompletionCelebration.shouldCelebrateSuccessfulNoteSave(saveResult: result) {
            store.triggerBreathingCelebration()
        }
        return true
    }

    @discardableResult
    func selectNote(_ note: NoteItem, store: NoteStore) -> Bool {
        guard resolveUnsavedChanges(store: store) else { return false }
        isHandlingNavigation = true
        store.selectedNoteID = note.id
        form.load(note)
        isHandlingNavigation = false
        return true
    }

    @discardableResult
    func beginNewNote(store: NoteStore) -> Bool {
        guard resolveUnsavedChanges(store: store) else { return false }
        isHandlingNavigation = true
        store.selectedNoteID = nil
        form.reset()
        requestTitleFocus = UUID()
        isHandlingNavigation = false
        return true
    }

    @discardableResult
    func resolveUnsavedChanges(store: NoteStore) -> Bool {
        switch NoteFormModel.unsavedChangesGuard(isDirty: form.isDirty) {
        case .allow:
            return true
        case .needsConfirmation:
            switch presentUnsavedChanges(unsavedChangesDisplayName()) {
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
    func confirmQuit(store: NoteStore) -> Bool {
        resolveUnsavedChanges(store: store)
    }

    private func unsavedChangesDisplayName() -> String {
        let trimmed = form.draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return form.isNew ? "New note" : "Untitled"
    }
}
