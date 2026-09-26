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
    @Environment(\.textZoom) private var textZoom
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var listFilter: TodoListFilter = .all

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
            CyberHeaderStrip {
                headerActions
            }
            HSplitView {
                todoListColumn
                detailColumn
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .background(MainWindowChromeConfigurator())
        .neonWindowFrame()
        .toolbar(.hidden, for: .windowToolbar)
        .toolbar(removing: .sidebarToggle)
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
                    .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                    .foregroundStyle(CyberpunkTheme.neonCyan)
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.black.opacity(0.35))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(CyberpunkTheme.neonCyan)
                            .frame(height: 1)
                    }
            }
        }
    }

    private var todoListColumn: some View {
        VStack(spacing: 0) {
            filterStrip
            TodoListContent(todos: filteredTodos) { todo in
                store.selectedTodoID = todo.id
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let todo = store.selectedTodo {
            TodoEditorView(todo: todo)
                .id(todo.id)
        } else {
            VStack(spacing: 12) {
                Text("Select a todo")
                    .font(AkashicFont.mono(AkashicFont.title, weight: .bold, zoom: textZoom))
                    .foregroundStyle(CyberpunkTheme.neonCyan)
                Text("Choose an item or add one from the header.")
                    .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                    .foregroundStyle(CyberpunkTheme.completedShaded)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            Button {
                store.addTodo()
            } label: {
                Image(systemName: "plus")
                    .imageScale(.medium)
            }
            .help("New todo")
            .buttonStyle(CyberHeaderIconButtonStyle())

            Button {
                store.importSeedFromBundle(replaceExisting: true)
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .imageScale(.medium)
            }
            .help("Import bundled demo seed (replace existing todos)")
            .buttonStyle(CyberHeaderIconButtonStyle())

            Button {
                importFromFile()
            } label: {
                Image(systemName: "doc.badge.arrow.up")
                    .imageScale(.medium)
            }
            .help("Import todos from JSON file…")
            .buttonStyle(CyberHeaderIconButtonStyle())

            Button {
                dismissWindow(id: "main")
            } label: {
                Text("×")
            }
            .help("Close main window")
            .buttonStyle(CyberHeaderIconButtonStyle())
        }
    }

    private var filterStrip: some View {
        HStack {
            Text(">")
                .font(AkashicFont.mono(AkashicFont.caption, weight: .bold, zoom: textZoom))
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
        .background(Color.black.opacity(0.22))
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
        panel.message = "Import seed JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.importSeedFromFile(url: url)
    }
}
