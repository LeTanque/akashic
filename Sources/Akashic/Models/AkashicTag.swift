import Foundation
import SwiftUI

/// User-defined tag with a theme palette color (stored once per tag name globally).
struct AkashicTag: Equatable, Sendable, Codable, Hashable, Identifiable {
    var name: String
    var color: AkashicTagColor

    var id: String { nameKey }

    var nameKey: String { name.lowercased() }

    init(name: String, color: AkashicTagColor = .defaultForNewTag) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed
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
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if normalized == "electricblue" { return .electricBlue }
        return AkashicTagColor(rawValue: normalized) ?? .defaultForNewTag
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
    static func normalizeNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in names {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let trimmed = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
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
