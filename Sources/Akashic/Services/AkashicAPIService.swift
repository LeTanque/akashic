import Combine
import Foundation

/// Shared gate for localhost API: data routes return 423 while the vault is locked.
@MainActor
final class AkashicAPIService: ObservableObject {
    @Published private(set) var isLocked: Bool = true

    private let apiLock = NSLock()
    private var apiLockedFlag: Bool = true

    /// Thread-safe read for the HTTP handler (off MainActor).
    nonisolated func isLockedForAPI() -> Bool {
        apiLock.lock()
        defer { apiLock.unlock() }
        return apiLockedFlag
    }

    func setLocked(_ locked: Bool) {
        isLocked = locked
        apiLock.lock()
        apiLockedFlag = locked
        apiLock.unlock()
    }
}
