import SwiftUI
import UniformTypeIdentifiers

private enum TodoListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"

    var id: String { rawValue }
}

struct MainWindowView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var listFilter: TodoListFilter = .all
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn

    private var filteredTodos: [TodoItem] {
        switch listFilter {
        case .all:
            store.todos
        case .active:
            store.todos.filter { !$0.completed }
        case .completed:
            store.todos.filter(\.completed)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            CyberHeaderStrip(title: "Akashic") {
                headerActions
            }
            NavigationSplitView(columnVisibility: $columnVisibility) {
                VStack(spacing: 0) {
                    filterStrip
                    List(selection: $store.selectedTodoID) {
                        ForEach(filteredTodos) { todo in
                            TodoRowView(
                                todo: todo,
                                compact: false,
                                onToggleComplete: { store.toggleCompletion(for: todo.id) },
                                onSelect: { store.selectedTodoID = todo.id }
                            )
                            .tag(todo.id)
                            .listRowBackground(CyberpunkTheme.background)
                            .listRowSeparatorTint(CyberpunkTheme.rowDivider)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
                }
            } detail: {
                if let todo = store.selectedTodo {
                    TodoEditorView(todo: todo)
                } else {
                    VStack(spacing: 12) {
                        Text("Select a todo")
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(CyberpunkTheme.neonCyan)
                        Text("Choose an item or add one from the toolbar.")
                            .font(.callout.monospaced())
                            .foregroundStyle(CyberpunkTheme.completedShaded)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CyberpunkTheme.background)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)
        }
        .frame(minWidth: 820, minHeight: 520)
        .background(CyberpunkTheme.background)
        .background(MainWindowChromeConfigurator())
        .neonWindowFrame(padding: 10)
        .preferredColorScheme(.dark)
        .tint(CyberpunkTheme.neonCyan)
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
                    .background(CyberpunkTheme.background)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(CyberpunkTheme.neonCyan)
                            .frame(height: 1)
                    }
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            Button {
                store.addTodo()
            } label: {
                Image(systemName: "plus")
            }
            .help("Add todo")
            .buttonStyle(CyberBorderedButtonStyle())

            Button {
                store.importSeedFromBundle(replaceExisting: true)
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Import seed")
            .buttonStyle(CyberBorderedButtonStyle())

            Button {
                importFromFile()
            } label: {
                Image(systemName: "doc.badge.arrow.up")
            }
            .help("Import JSON…")
            .buttonStyle(CyberBorderedButtonStyle())

            Button {
                dismissWindow(id: "main")
            } label: {
                Text("×")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
            .help("Close window")
            .buttonStyle(CyberBorderedButtonStyle())
        }
    }

    private var filterStrip: some View {
        HStack {
            Text(">")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(CyberpunkTheme.neonCyan)
            Picker("Filter", selection: $listFilter) {
                ForEach(TodoListFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(CyberpunkTheme.bodyBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CyberpunkTheme.rowDivider)
                .frame(height: 1)
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
