import SwiftUI

/// Shared todo stack used by the main window and the menu-bar popover.
/// `List` + `onMove` gives native click-hold-drag without stealing row taps.
struct TodoListContent: View {
    @EnvironmentObject private var store: TodoStore

    let todos: [TodoItem]
    var compact: Bool = false
    let onSelect: (TodoItem) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(todos) { todo in
                    TodoRowView(
                        todo: todo,
                        compact: compact,
                        onToggleComplete: { store.toggleCompletion(for: todo.id) },
                        onSelect: { onSelect(todo) }
                    )
                    .id(todo.id)
                    .listRowInsets(EdgeInsets(
                        top: 0,
                        leading: compact ? 12 : 8,
                        bottom: 0,
                        trailing: compact ? 12 : 8
                    ))
                    .listRowSeparator(.hidden)
                    .listRowBackground(rowBackground(for: todo))
                    .contentShape(Rectangle())
                    .overlay(alignment: .bottom) {
                        if compact {
                            Divider().overlay(CyberpunkTheme.rowDivider)
                        } else {
                            Rectangle()
                                .fill(CyberpunkTheme.rowDivider)
                                .frame(height: 1)
                        }
                    }
                }
                .onMove { source, destination in
                    store.moveTodos(from: source, to: destination, in: todos)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .onChange(of: store.revealTodoInListID) { _, id in
                guard let id, todos.contains(where: { $0.id == id }) else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }

    private func rowBackground(for todo: TodoItem) -> Color {
        store.selectedTodoID == todo.id
            ? CyberpunkTheme.completedShaded.opacity(0.28)
            : Color.clear
    }
}
