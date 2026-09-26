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
    /// Stable manual list position. Lower values stack higher.
    var sortOrder: Int

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
            completedAt: nil,
            sortOrder: 0
        )
    }

    /// Baseline order used when assigning `sortOrder` (high → medium → low, then recency).
    /// Completed items always sort last. Manual drag can override this later.
    static func defaultStackOrder(_ lhs: TodoItem, _ rhs: TodoItem) -> Bool {
        if lhs.completed != rhs.completed { return !lhs.completed && rhs.completed }
        if lhs.priority.sortOrder != rhs.priority.sortOrder {
            return lhs.priority.sortOrder < rhs.priority.sortOrder
        }
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.createdOn > rhs.createdOn
    }

    func hasSameEditableContent(as other: TodoItem) -> Bool {
        id == other.id
            && title == other.title
            && description == other.description
            && priority == other.priority
            && completeBy == other.completeBy
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
        case sortOrder = "sort_order"
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
        sortOrder = row[Columns.sortOrder]
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
        container[Columns.sortOrder] = sortOrder
    }
}
