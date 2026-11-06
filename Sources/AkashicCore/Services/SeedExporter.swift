import Foundation

public struct CyberpunkSeedExportFile: Encodable, Sendable {
    public let source: String
    public let todos: [CyberpunkSeedExportTodo]
}

public struct CyberpunkSeedExportTodo: Encodable, Sendable {
    public let id: Int
    public let title: String
    public let completed: Bool
    public let priority: String
    public let created_at: String
    public let updated_at: String
}

public enum SeedExporter {
    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    public static func exportFile(from todos: [TodoItem], source: String = "akashic export") -> CyberpunkSeedExportFile {
        let isoFormatter = makeISOFormatter()
        let ordered = todos.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return lhs.updatedAt > rhs.updatedAt
        }
        let rows = ordered.enumerated().map { index, item in
            CyberpunkSeedExportTodo(
                id: index + 1,
                title: item.title,
                completed: item.completed,
                priority: item.priority.rawValue,
                created_at: isoFormatter.string(from: item.createdOn),
                updated_at: isoFormatter.string(from: item.updatedAt)
            )
        }
        return CyberpunkSeedExportFile(source: source, todos: rows)
    }

    public static func encodeJSON(from todos: [TodoItem], source: String = "akashic export") throws -> Data {
        let file = exportFile(from: todos, source: source)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }
}
