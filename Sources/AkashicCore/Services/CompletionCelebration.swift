import Foundation

public enum CompletionCelebration {
    /// Fire window feedback only when a todo transitions to completed.
    public static func shouldCelebrate(wasCompleted: Bool, nowCompleted: Bool) -> Bool {
        !wasCompleted && nowCompleted
    }

    /// Fire the same breathing border effect after a todo form Save persists (new or updated).
    public static func shouldCelebrateSuccessfulSave(saveResult: TodoFormSaveResult?) -> Bool {
        saveResult != nil
    }

    public static func shouldCelebrateSuccessfulNoteSave(saveResult: NoteFormSaveResult?) -> Bool {
        saveResult != nil
    }
}
