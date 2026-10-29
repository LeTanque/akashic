import Foundation
import SwiftUI

/// User-defined tag with a theme palette color (stored once per tag name globally).
struct AkashicTag: Equatable, Sendable, Codable, Hashable, Identifiable {
    var name: String
    var color: AkashicTagColor

    var id: String { nameKey }

    var nameKey: String { name.lowercased() }

    init(name: String, color: AkashicTagColor = .defaultForNewTag) {
        self.name = NoteTagNormalization.clampedName(name)
        self.color = color
    }
}

enum AkashicTagColor: String, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case cyan
    case electricBlue = "electric_blue"
    case orange
    case magenta
    case purple
    case green
    case yellow
    case red
    case gray

    var id: String { rawValue }

    static let defaultForNewTag: AkashicTagColor = .cyan

    static func validated(_ raw: String?) -> AkashicTagColor {
        guard let raw else { return .defaultForNewTag }
        return parseStrict(raw) ?? .defaultForNewTag
    }

    /// Returns nil when `raw` is not a known palette name (API PATCH validation).
    static func parseStrict(_ raw: String) -> AkashicTagColor? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if normalized == "electricblue" { return .electricBlue }
        return AkashicTagColor(rawValue: normalized)
    }

    var swiftUIColor: Color {
        switch self {
        case .cyan:
            CyberpunkTheme.neonCyan
        case .electricBlue:
            Color(red: 0.2, green: 0.55, blue: 1)
        case .orange:
            CyberpunkTheme.neonOrange
        case .magenta:
            Color(red: 1, green: 0.2, blue: 0.75)
        case .purple:
            Color(red: 0.65, green: 0.35, blue: 1)
        case .green:
            Color(red: 0.2, green: 0.95, blue: 0.45)
        case .yellow:
            Color(red: 1, green: 0.92, blue: 0.2)
        case .red:
            Color(red: 1, green: 0.28, blue: 0.28)
        case .gray:
            Color(red: 0.55, green: 0.58, blue: 0.62)
        }
    }
}

enum NoteTagNormalization {
    static let maxNameLength = 24

    static func clampedName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    static func nameWithinLimit(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxNameLength
    }

    /// Returns an error message when any tag name in API JSON exceeds the limit.
    static func apiTagNameLengthError(in json: Any?) -> String? {
        guard let json else { return nil }
        let names = rawTagNames(from: json)
        if names.contains(where: { !nameWithinLimit($0) }) {
            return "tag name must be at most \(maxNameLength) characters"
        }
        return nil
    }

    private static func rawTagNames(from json: Any) -> [String] {
        if let strings = json as? [String] {
            return strings
        }
        if let objects = json as? [[String: Any]] {
            return objects.compactMap { $0["name"] as? String }
        }
        if let mixed = json as? [Any] {
            return mixed.flatMap { element -> [String] in
                if let name = element as? String { return [name] }
                if let dict = element as? [String: Any], let name = dict["name"] as? String { return [name] }
                return []
            }
        }
        return []
    }

    static func normalizeNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names {
            let trimmed = clampedName(raw)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    static func normalizeTags(_ tags: [AkashicTag]) -> [AkashicTag] {
        var seen = Set<String>()
        var result: [AkashicTag] = []
        for tag in tags {
            let trimmed = clampedName(tag.name)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(AkashicTag(name: trimmed, color: tag.color))
        }
        return result
    }

    static func parseInput(_ text: String) -> [String] {
        let parts = text.split { $0 == "," || $0 == "\n" }
        return normalizeNames(parts.map(String.init))
    }

    static func tagNameSet(_ tags: [AkashicTag]) -> Set<String> {
        Set(tags.map { $0.name.lowercased() })
    }
}
