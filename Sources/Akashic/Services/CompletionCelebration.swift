import Foundation

enum CompletionCelebration {
    /// Fire window feedback only when a todo transitions to completed.
    static func shouldCelebrate(wasCompleted: Bool, nowCompleted: Bool) -> Bool {
        !wasCompleted && nowCompleted
    }

    /// Fire the same breathing border effect after a todo form Save persists (new or updated).
    static func shouldCelebrateSuccessfulSave(saveResult: TodoFormSaveResult?) -> Bool {
        saveResult != nil
    }

    static func shouldCelebrateSuccessfulNoteSave(saveResult: NoteFormSaveResult?) -> Bool {
        saveResult != nil
    }
}
