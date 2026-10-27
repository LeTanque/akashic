import Foundation

/// Draft vs saved due date for the themed picker (testable commit/cancel flow).
struct DueDateDraft: Equatable {
    private(set) var saved: Date?
    private(set) var pending: Date?

    init(saved: Date?) {
        self.saved = saved
        self.pending = saved
    }

    var hasChanges: Bool {
        !Self.sameInstant(saved, pending)
    }

    mutating func select(_ date: Date) {
        pending = date
    }

    /// Clears the pending due date (committed only after `commit()`).
    mutating func clearPending() {
        pending = nil
    }

    /// Applies pending to saved and returns the value to persist.
    @discardableResult
    mutating func commit() -> Date? {
        saved = pending
        return saved
    }

    mutating func cancel() {
        pending = saved
    }

    mutating func syncSaved(_ newSaved: Date?) {
        saved = newSaved
        pending = newSaved
    }

    private static func sameInstant(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return abs(left.timeIntervalSince(right)) < 0.5
        default:
            return false
        }
    }
}
