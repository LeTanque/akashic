import Foundation

/// Per-device logical time: maps device UUID → last seen HLC from that device.
public struct VersionVector: Equatable, Hashable, Sendable, Codable {
    public private(set) var map: [UUID: HybridLogicalClock]

    public init(map: [UUID: HybridLogicalClock] = [:]) {
        self.map = map
    }

    public subscript(device id: UUID) -> HybridLogicalClock? {
        map[id]
    }

    public mutating func set(_ clock: HybridLogicalClock) {
        if let existing = map[clock.deviceId] {
            if clock > existing { map[clock.deviceId] = clock }
        } else {
            map[clock.deviceId] = clock
        }
    }

    public mutating func mergeMax(with other: VersionVector) {
        for (_, clock) in other.map {
            set(clock)
        }
    }

    /// True if `ancestor`'s version is component-wise ≤ descendant's (causal precedence).
    public static func descends(from ancestor: VersionVector, to descendant: VersionVector) -> Bool {
        for (device, aClock) in ancestor.map {
            guard let dClock = descendant.map[device] else { return false }
            if aClock > dClock { return false }
        }
        return true
    }

    /// Combined vector used as merged record parent identity (component-wise max by HLC).
    public static func merged(_ lhs: VersionVector, _ rhs: VersionVector) -> VersionVector {
        var out = lhs
        out.mergeMax(with: rhs)
        return out
    }

    enum CodingKeys: String, CodingKey {
        case map
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringKeyed = try container.decode([String: HybridLogicalClock].self)
        var parsed: [UUID: HybridLogicalClock] = [:]
        for (key, value) in stringKeyed {
            guard let id = UUID(uuidString: key) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "bad uuid in version vector")
            }
            parsed[id] = value
        }
        self.map = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var stringKeyed: [String: HybridLogicalClock] = [:]
        for (id, clock) in map {
            stringKeyed[id.uuidString] = clock
        }
        try container.encode(stringKeyed)
    }
}
