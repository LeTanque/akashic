import Foundation

struct CyberpunkSeedExportFile: Encodable {
    let source: String
    let todos: [CyberpunkSeedExportTodo]
}

struct CyberpunkSeedExportTodo: Encodable {
    let id: Int
    let title: String
    let completed: Bool
    let priority: String
    let created_at: String
    let updated_at: String
}

enum SeedExporter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func exportFile(from todos: [TodoItem], source: String = "akashic export") -> CyberpunkSeedExportFile {
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

    static func encodeJSON(from todos: [TodoItem], source: String = "akashic export") throws -> Data {
        let file = exportFile(from: todos, source: source)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }
}
