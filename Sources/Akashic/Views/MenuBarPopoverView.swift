import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(CyberpunkTheme.border)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.todos) { todo in
                        TodoRowView(
                            todo: todo,
                            compact: true,
                            onToggleComplete: { store.toggleCompletion(for: todo.id) },
                            onSelect: {
                                store.selectedTodoID = todo.id
                                openWindow(id: "main")
                            }
                        )
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)
            footer
        }
        .frame(width: 380)
        .background {
            ZStack {
                CyberpunkTheme.background
                GlassBackground(material: .popover, blendingMode: .withinWindow)
                    .opacity(0.85)
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Akashic")
                .font(.headline.weight(.bold))
                .foregroundStyle(CyberpunkTheme.neonCyan)
            Spacer()
            Text("\(store.todos.filter { !$0.completed }.count) open")
                .font(.caption.monospaced())
                .foregroundStyle(CyberpunkTheme.textSecondary)
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            Button {
                store.addTodo()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)

            Spacer()

            Button("Open Akashic") {
                if store.selectedTodoID == nil {
                    store.selectedTodoID = store.todos.first?.id
                }
                openWindow(id: "main")
            }
            .buttonStyle(.borderedProminent)
            .tint(CyberpunkTheme.neonMagenta.opacity(0.85))
        }
        .padding(12)
    }
}
