import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @EnvironmentObject private var store: TodoStore

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedTodoID) {
                ForEach(store.todos) { todo in
                    TodoRowView(
                        todo: todo,
                        compact: false,
                        onToggleComplete: { store.toggleCompletion(for: todo.id) },
                        onSelect: { store.selectedTodoID = todo.id }
                    )
                    .tag(todo.id)
                    .listRowBackground(CyberpunkTheme.panel.opacity(0.35))
                }
            }
            .scrollContentBackground(.hidden)
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
        } detail: {
            if let todo = store.selectedTodo {
                TodoEditorView(todo: todo)
            } else {
                ContentUnavailableView(
                    "Select a todo",
                    systemImage: "checklist",
                    description: Text("Choose an item or add one from the toolbar.")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.addTodo()
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Button {
                    store.importSeedFromBundle(replaceExisting: true)
                } label: {
                    Label("Import seed", systemImage: "square.and.arrow.down")
                }
                Button {
                    importFromFile()
                } label: {
                    Label("Import JSON…", systemImage: "doc.badge.arrow.up")
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .background {
            ZStack {
                CyberpunkTheme.background
                GlassBackground(material: .underWindowBackground, blendingMode: .behindWindow)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if store.selectedTodoID == nil {
                store.selectedTodoID = store.todos.first?.id
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = store.lastImportMessage {
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(CyberpunkTheme.neonCyan)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(CyberpunkTheme.panel.opacity(0.9))
            }
        }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Import cyberpunk2044 seed JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.importSeedFromFile(url: url)
    }
}
