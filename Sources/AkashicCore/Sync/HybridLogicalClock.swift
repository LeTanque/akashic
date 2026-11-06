import Foundation

/// Hybrid logical clock: wall milliseconds, per-wall counter, and device id for total ordering.
public struct HybridLogicalClock: Equatable, Hashable, Sendable, Codable, Comparable {
    public var wallMillis: UInt64
    public var counter: UInt32
    public var deviceId: UUID

    enum CodingKeys: String, CodingKey {
        case wallMillis = "wall_ms"
        case counter
        case deviceId = "device_id"
    }

    public init(wallMillis: UInt64, counter: UInt32, deviceId: UUID) {
        self.wallMillis = wallMillis
        self.counter = counter
        self.deviceId = deviceId
    }

    public static func < (lhs: HybridLogicalClock, rhs: HybridLogicalClock) -> Bool {
        if lhs.wallMillis != rhs.wallMillis { return lhs.wallMillis < rhs.wallMillis }
        if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
        return lhs.deviceId.uuidString.lowercased() < rhs.deviceId.uuidString.lowercased()
    }

    /// Deterministic tie-break for conflict concatenation (HLC order, then device id).
    public static func lexicographicCompare(_ lhs: HybridLogicalClock, _ rhs: HybridLogicalClock) -> Bool {
        lhs < rhs
    }
}

/// HLC generator for one installation (`deviceId`). Safe to use from database write closures.
public final class HybridLogicalClockSource: @unchecked Sendable {
    public let deviceId: UUID

    private let lock = NSLock()
    private var lastWallMillis: UInt64 = 0
    private var lastCounter: UInt32 = 0

    public init(deviceId: UUID) {
        self.deviceId = deviceId
    }

    private static func physicalMillis() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }

    /// Emit a clock for a new local event.
    public func tick() -> HybridLogicalClock {
        lock.lock()
        defer { lock.unlock() }
        let pt = Self.physicalMillis()
        let t = max(lastWallMillis, pt)
        let nextCounter: UInt32
        if t == lastWallMillis {
            nextCounter = lastCounter &+ 1
        } else {
            nextCounter = 0
        }
        lastWallMillis = t
        lastCounter = nextCounter
        return HybridLogicalClock(wallMillis: lastWallMillis, counter: nextCounter, deviceId: deviceId)
    }

    /// Advance state from a remotely observed clock.
    public func receive(_ remote: HybridLogicalClock) {
        lock.lock()
        defer { lock.unlock() }
        let pt = Self.physicalMillis()
        let t = max(lastWallMillis, pt, remote.wallMillis)
        let nextCounter: UInt32
        if t == lastWallMillis, t == remote.wallMillis {
            nextCounter = max(lastCounter, remote.counter) &+ 1
        } else if t == lastWallMillis {
            nextCounter = lastCounter &+ 1
        } else if t == remote.wallMillis {
            nextCounter = remote.counter &+ 1
        } else {
            nextCounter = 0
        }
        lastWallMillis = t
        lastCounter = nextCounter
    }
}
