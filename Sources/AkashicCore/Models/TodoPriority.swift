import Foundation

public enum TodoPriority: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low

    public var label: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }

    public var sortOrder: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }
}
