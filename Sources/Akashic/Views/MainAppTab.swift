import Foundation

/// Session-only workspace tab (defaults to todos on each launch).
enum MainAppTab: String, CaseIterable, Identifiable {
    case todos
    case notes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .todos: "Todos"
        case .notes: "Notes"
        }
    }
}
