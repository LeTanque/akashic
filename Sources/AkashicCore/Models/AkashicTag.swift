import Foundation

/// User-defined tag (display). Stable sync identity lives on `TagRecord` (`syncId`).
public struct AkashicTag: Equatable, Sendable, Codable, Hashable, Identifiable {
    public var name: String
    public var color: AkashicTagColor

    /// Sorted list / chip identity remains the normalized name key (existing behavior).
    public var id: String { nameKey }

    public var nameKey: String { name.lowercased() }

    public init(name: String, color: AkashicTagColor = .defaultForNewTag) {
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.color = color
    }
}

public enum AkashicTagColor: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case cyan
    case electricBlue = "electric_blue"
    case orange
    case magenta
    case purple
    case green
    case yellow
    case red
    case gray

    public var id: String { rawValue }

    public static let defaultForNewTag: AkashicTagColor = .cyan

    public static func validated(_ raw: String?) -> AkashicTagColor {
        guard let raw else { return .defaultForNewTag }
        return parseStrict(raw) ?? .defaultForNewTag
    }

    /// Returns nil when `raw` is not a known palette name (API PATCH validation).
    public static func parseStrict(_ raw: String) -> AkashicTagColor? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if normalized == "electricblue" { return .electricBlue }
        return AkashicTagColor(rawValue: normalized)
    }
}
