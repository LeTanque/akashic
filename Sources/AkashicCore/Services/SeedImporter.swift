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

public enum SeedImporter {
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

    public static func parseSeedData(_ data: Data) throws -> [TodoItem] {
        let seed = try JSONDecoder().decode(CyberpunkSeedFile.self, from: data)
        return seed.todos.map { map($0) }
    }

    public static func bundledSeedData() -> Data? {
        guard let url = Bundle.module.url(forResource: "akashic-seed-todos", withExtension: "json") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    public static func importItems(_ items: [TodoItem], into db: DatabaseQueue, replaceExisting: Bool) throws -> Int {
        let ordered = items.sorted(by: TodoItem.defaultStackOrder)
        return try db.write { database in
            let installation = try InstallationContext.loadOrCreate(in: database)
            if replaceExisting {
                try TodoItem.deleteAll(database)
            }
            let base: Int
            if replaceExisting {
                base = 0
            } else {
                let maxOrder = try Int.fetchOne(
                    database,
                    sql: "SELECT MAX(sort_order) FROM \(TodoItem.databaseTableName) WHERE deleted_at IS NULL"
                )
                base = (maxOrder ?? -1) + 1
            }
            for (index, var item) in ordered.enumerated() {
                let clock = installation.tick()
                item.sortOrder = base + index
                item.hlc = clock
                item.deletedAt = nil
                item.fieldClocks = FieldClockMap(fields: [
                    "title": clock,
                    "description": clock,
                    "completed": clock,
                    "priority": clock,
                    "complete_by": clock,
                    "completed_at": clock,
                    "sort_order": clock,
                ])
                item.version = VersionVector(map: [installation.deviceId: clock])
                try item.insert(database)
                try ChangeLogEntry(
                    recordID: item.id.uuidString,
                    entity: .todo,
                    fieldChanges: ["seed_import": "1"],
                    hlc: clock,
                    deviceID: installation.deviceId
                ).insert(database)
            }
            return ordered.count
        }
    }

    private static func map(_ seed: CyberpunkSeedTodo) -> TodoItem {
        let created = parseDate(seed.created_at) ?? Date()
        let updated = parseDate(seed.updated_at) ?? created
        let priority = TodoPriority(rawValue: seed.priority) ?? .medium
        let completedAt: Date? = seed.completed ? updated : nil
        let ph = SyncPlaceholder.draftHLC

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
            sortOrder: 0,
            hlc: ph,
            deletedAt: nil,
            fieldClocks: .empty,
            version: VersionVector()
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }
}
