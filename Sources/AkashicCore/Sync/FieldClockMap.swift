import Foundation

/// JSON-serializable map from field name → HLC of last writer for that field.
public struct FieldClockMap: Equatable, Hashable, Sendable, Codable {
    public private(set) var fields: [String: HybridLogicalClock]

    public init(fields: [String: HybridLogicalClock] = [:]) {
        self.fields = fields
    }

    public subscript(field: String) -> HybridLogicalClock? {
        get { fields[field] }
        set {
            if let v = newValue { fields[field] = v } else { fields.removeValue(forKey: field) }
        }
    }

    public mutating func set(_ clock: HybridLogicalClock, for field: String) {
        fields[field] = clock
    }

    public mutating func removeField(_ name: String) {
        fields.removeValue(forKey: name)
    }

    public mutating func mergeMax(with other: FieldClockMap) {
        for (key, clock) in other.fields {
            if let existing = fields[key] {
                if clock > existing { fields[key] = clock }
            } else {
                fields[key] = clock
            }
        }
    }

    public static let empty = FieldClockMap()
}
