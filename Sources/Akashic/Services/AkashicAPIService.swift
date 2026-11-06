import Combine
import Foundation

/// Shared gate for localhost API: data routes return 423 while the vault is locked.
@MainActor
final class AkashicAPIService: ObservableObject {
    @Published private(set) var isLocked: Bool = true

    /// Lock flag readable from the HTTP thread without hopping to MainActor.
    private let apiLockFlag = LockedBool(initial: true)

    /// Thread-safe read for the HTTP handler (off MainActor).
    nonisolated func isLockedForAPI() -> Bool {
        apiLockFlag.value
    }

    func setLocked(_ locked: Bool) {
        isLocked = locked
        apiLockFlag.value = locked
    }
}

/// Tiny lock-guarded Bool; `@unchecked Sendable` justified by `NSLock`.
private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: Bool

    init(initial: Bool) { raw = initial }

    var value: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return raw
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            raw = newValue
        }
    }
}
