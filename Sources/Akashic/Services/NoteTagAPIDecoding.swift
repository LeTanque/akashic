import Foundation

enum NoteTagAPIDecoding {
    /// Accepts `[{"name":"work","color":"cyan"}]`, `["work","ideas"]`, or a mixed array.
    static func decodeTags(from json: Any?) -> [AkashicTag] {
        guard let json else { return [] }
        if let strings = json as? [String] {
            return NoteTagNormalization.normalizeTags(
                strings.map { AkashicTag(name: $0, color: .defaultForNewTag) }
            )
        }
        if let objects = json as? [[String: Any]] {
            return NoteTagNormalization.normalizeTags(decodeTagObjects(objects))
        }
        if let mixed = json as? [Any] {
            var tags: [AkashicTag] = []
            for element in mixed {
                if let name = element as? String {
                    tags.append(AkashicTag(name: name, color: .defaultForNewTag))
                } else if let dict = element as? [String: Any] {
                    tags.append(contentsOf: decodeTagObjects([dict]))
                }
            }
            return NoteTagNormalization.normalizeTags(tags)
        }
        return []
    }

    private static func decodeTagObjects(_ objects: [[String: Any]]) -> [AkashicTag] {
        objects.compactMap { dict -> AkashicTag? in
            guard let name = dict["name"] as? String else { return nil }
            let color = AkashicTagColor.validated(dict["color"] as? String)
            return AkashicTag(name: name, color: color)
        }
    }

    static func decodeTagsJSONData(_ data: Data) -> [AkashicTag] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return decodeTags(from: raw)
    }
}
