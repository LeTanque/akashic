import Foundation

enum NoteTagAPIDecoding {
    /// Accepts `[{"name":"work","color":"cyan"}]` or `["work","ideas"]`.
    static func decodeTags(from json: Any?) -> [AkashicTag] {
        guard let json else { return [] }
        if let strings = json as? [String] {
            return NoteTagNormalization.normalizeTags(
                strings.map { AkashicTag(name: $0, color: .defaultForNewTag) }
            )
        }
        if let objects = json as? [[String: Any]] {
            let tags = objects.compactMap { dict -> AkashicTag? in
                guard let name = dict["name"] as? String else { return nil }
                let color = AkashicTagColor.validated(dict["color"] as? String)
                return AkashicTag(name: name, color: color)
            }
            return NoteTagNormalization.normalizeTags(tags)
        }
        return []
    }

    static func decodeTagsJSONData(_ data: Data) -> [AkashicTag] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return decodeTags(from: raw)
    }
}
