import Foundation

enum CompletionCelebration {
    /// Fire window feedback only when a todo transitions to completed.
    static func shouldCelebrate(wasCompleted: Bool, nowCompleted: Bool) -> Bool {
        !wasCompleted && nowCompleted
    }
}
