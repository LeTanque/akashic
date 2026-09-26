import Foundation
import GRDB

struct CyberpunkSeedFile: Decodable {
    let source: String
    let todos: [CyberpunkSeedTodo]
}

struct CyberpunkSeedTodo: Decodable {
    let id: Int
    let title: String
    let completed: Bool
    let priority: String
    let created_at: String
    let updated_at: String
}

enum SeedImporter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseSeedData(_ data: Data) throws -> [TodoItem] {
        let seed = try JSONDecoder().decode(CyberpunkSeedFile.self, from: data)
        return seed.todos.map { map($0) }
    }

    static func bundledSeedData() -> Data? {
        guard let url = Bundle.module.url(forResource: "akashic-seed-todos", withExtension: "json") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    static func importItems(_ items: [TodoItem], into db: DatabaseQueue, replaceExisting: Bool) throws -> Int {
        let ordered = items.sorted(by: TodoItem.defaultStackOrder)
        return try db.write { database in
            if replaceExisting {
                try TodoItem.deleteAll(database)
            }
            let base: Int
            if replaceExisting {
                base = 0
            } else {
                let maxOrder = try Int.fetchOne(
                    database,
                    sql: "SELECT MAX(sort_order) FROM \(TodoItem.databaseTableName)"
                )
                base = (maxOrder ?? -1) + 1
            }
            for (index, item) in ordered.enumerated() {
                var copy = item
                copy.sortOrder = base + index
                try copy.insert(database)
            }
            return ordered.count
        }
    }

    private static func map(_ seed: CyberpunkSeedTodo) -> TodoItem {
        let created = parseDate(seed.created_at) ?? Date()
        let updated = parseDate(seed.updated_at) ?? created
        let priority = TodoPriority(rawValue: seed.priority) ?? .medium
        let completedAt: Date? = seed.completed ? updated : nil

        return TodoItem(
            id: UUID(),
            title: seed.title,
            description: "",
            completed: seed.completed,
            priority: priority,
            completeBy: nil,
            createdOn: created,
            updatedAt: updated,
            completedAt: completedAt,
            sortOrder: 0
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }
}
