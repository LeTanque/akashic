import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.textZoom) private var textZoom

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(CyberpunkTheme.neonCyan)
                .frame(height: 1)
                .shadow(color: CyberpunkTheme.neonCyan.opacity(0.45), radius: 3)
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
                        Divider()
                            .overlay(CyberpunkTheme.rowDivider)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)
            Rectangle()
                .fill(CyberpunkTheme.rowDivider)
                .frame(height: 1)
            footer
        }
        .frame(width: 380)
        .background(CyberpunkTheme.background)
        .overlay {
            Rectangle()
                .stroke(CyberpunkTheme.neonCyan, lineWidth: 1)
        }
        .shadow(color: CyberpunkTheme.neonCyan.opacity(0.55), radius: 7)
        .preferredColorScheme(.dark)
        .tint(CyberpunkTheme.neonCyan)
    }

    private var header: some View {
        HStack {
            Text("Akashic")
                .font(AkashicFont.mono(AkashicFont.headline, weight: .bold, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.neonCyan)
            Spacer()
            Text("\(store.todos.filter { !$0.completed }.count) open")
                .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.completedShaded)
        }
        .padding(12)
        .background(CyberpunkTheme.background)
    }

    private var footer: some View {
        HStack {
            Button {
                store.addTodo()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(CyberBorderedButtonStyle())
            .keyboardShortcut("n", modifiers: .command)

            Spacer()

            Button("Open Akashic") {
                if store.selectedTodoID == nil {
                    store.selectedTodoID = store.todos.first?.id
                }
                openWindow(id: "main")
            }
            .buttonStyle(CyberBorderedButtonStyle())
        }
        .padding(12)
        .background(CyberpunkTheme.background)
    }
}
