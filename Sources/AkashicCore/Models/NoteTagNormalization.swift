import Foundation

public enum NoteTagNormalization {
    public static let maxNameLength = 24

    public static func clampedName(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
    }

    public static func nameWithinLimit(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxNameLength
    }

    /// Returns an error message when any tag name in API JSON exceeds the limit.
    public static func apiTagNameLengthError(in json: Any?) -> String? {
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

    public static func normalizeNames(_ names: [String]) -> [String] {
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

    public static func normalizeTags(_ tags: [AkashicTag]) -> [AkashicTag] {
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

    /// Caps each comma/newline-separated segment of the tag input at `maxNameLength`,
    /// keeping the separators so Return still commits a full-length tag.
    public static func capTagInput(_ text: String) -> String {
        var result = ""
        var segmentCount = 0
        for character in text {
            if character == "," || character == "\n" {
                result.append(character)
                segmentCount = 0
            } else if segmentCount < maxNameLength {
                result.append(character)
                segmentCount += 1
            }
        }
        return result
    }

    public static func parseInput(_ text: String) -> [String] {
        let parts = text.split { $0 == "," || $0 == "\n" }
        return normalizeNames(parts.map(String.init))
    }

    public static func tagNameSet(_ tags: [AkashicTag]) -> Set<String> {
        Set(tags.map { $0.name.lowercased() })
    }
}
