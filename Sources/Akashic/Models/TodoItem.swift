import Foundation
import GRDB

struct TodoItem: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var description: String
    var completed: Bool
    var priority: TodoPriority
    var completeBy: Date?
    var createdOn: Date
    var updatedAt: Date
    var completedAt: Date?

    static func new(
        title: String = "",
        description: String = "",
        priority: TodoPriority = .medium
    ) -> TodoItem {
        let now = Date()
        return TodoItem(
            id: UUID(),
            title: title,
            description: description,
            completed: false,
            priority: priority,
            completeBy: nil,
            createdOn: now,
            updatedAt: now,
            completedAt: nil
        )
    }
}

extension TodoItem: FetchableRecord, PersistableRecord {
    static let databaseTableName = "todos"

    enum Columns: String, ColumnExpression {
        case id, title, description, completed, priority
        case completeBy = "complete_by"
        case createdOn = "created_on"
        case updatedAt = "updated_at"
        case completedAt = "completed_at"
    }

    init(row: Row) {
        id = UUID(uuidString: row[Columns.id]) ?? UUID()
        title = row[Columns.title]
        description = row[Columns.description]
        completed = row[Columns.completed]
        priority = TodoPriority(rawValue: row[Columns.priority]) ?? .medium
        completeBy = row[Columns.completeBy]
        createdOn = row[Columns.createdOn]
        updatedAt = row[Columns.updatedAt]
        completedAt = row[Columns.completedAt]
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.title] = title
        container[Columns.description] = description
        container[Columns.completed] = completed
        container[Columns.priority] = priority.rawValue
        container[Columns.completeBy] = completeBy
        container[Columns.createdOn] = createdOn
        container[Columns.updatedAt] = updatedAt
        container[Columns.completedAt] = completedAt
    }
}
