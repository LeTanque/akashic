import SwiftUI

private enum TodoListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"

    var id: String { rawValue }
}

struct MainWindowView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var editorSession: TodoEditorSession
    @EnvironmentObject private var sidebarVisibility: SidebarVisibilityStore
    @EnvironmentObject private var mainSectionVisibility: MainSectionVisibilityStore
    @Environment(\.textZoom) private var textZoom
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
            mainContent
        }
        .overlay {
            BorderCelebrationOverlay(
                completionCelebrationID: store.completionCelebrationID,
                deletionCelebrationID: store.deletionCelebrationID
            )
        }
        .frame(minWidth: 820, minHeight: 520)
        .background(MainWindowChromeConfigurator())
        .background(WindowUnsavedChangesGuard(session: editorSession, store: store))
        .neonWindowFrame()
        .toolbar(.hidden, for: .windowToolbar)
        .toolbar(removing: .sidebarToggle)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .tint(CyberpunkTheme.neonCyan)
        .onChange(of: store.selectedTodoID) { _, newID in
            editorSession.syncToSelection(store: store, selectedID: newID)
        }
        .onAppear {
            editorSession.syncToSelection(store: store, selectedID: store.selectedTodoID)
        }
    }

    private var showsMatrixRain: Bool {
        !sidebarVisibility.isVisible && !mainSectionVisibility.isVisible
    }

    /// Sidebar alone should fill the content area under the header (mirror of detail full width when sidebar is hidden).
    private var sidebarExpandsToFill: Bool {
        sidebarVisibility.isVisible && !mainSectionVisibility.isVisible
    }

    @ViewBuilder
    private var mainContent: some View {
        if showsMatrixRain {
            MatrixDigitalRainView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                if sidebarVisibility.isVisible {
                    todoListColumn
                }
                if mainSectionVisibility.isVisible {
                    detailColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var todoListColumn: some View {
        let list = VStack(spacing: 0) {
            filterStrip
            TodoListContent(todos: filteredTodos) { todo in
                _ = editorSession.selectTodo(todo, store: store)
            }
        }
        if sidebarExpandsToFill {
            list.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list.frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        TodoEditorView(session: editorSession)
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            Button {
                _ = editorSession.beginNewTodo(store: store)
            } label: {
                Image(systemName: "plus")
                    .imageScale(.medium)
            }
            .help("New todo")
            .buttonStyle(CyberHeaderIconButtonStyle())

            Button {
                sidebarVisibility.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
                    .imageScale(.medium)
            }
            .help(sidebarVisibility.headerTooltip)
            .buttonStyle(CyberHeaderIconButtonStyle())

            Button {
                guard editorSession.resolveUnsavedChanges(store: store) else { return }
                mainSectionVisibility.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .imageScale(.medium)
            }
            .help(mainSectionVisibility.headerTooltip)
            .buttonStyle(CyberHeaderIconButtonStyle())
        }
    }

    private var filterStrip: some View {
        HStack {
            Text(">")
                .font(AkashicFont.mono(AkashicFont.caption, weight: .bold, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.neonCyan)
            ThemedDropdown(
                accessibilityTitle: "Filter",
                selection: $listFilter,
                options: Array(TodoListFilter.allCases),
                label: { $0.rawValue }
            )
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
}

/// Blocks window close while the todo form has unsaved edits.
private struct WindowUnsavedChangesGuard: NSViewRepresentable {
    let session: TodoEditorSession
    let store: TodoStore

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, store: store)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.session = session
        context.coordinator.store = store
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var session: TodoEditorSession
        var store: TodoStore
        private weak var window: NSWindow?

        init(session: TodoEditorSession, store: TodoStore) {
            self.session = session
            self.store = store
        }

        func attach(to view: NSView) {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = view.window else { return }
                if self.window !== window {
                    self.window?.delegate = nil
                    self.window = window
                    window.delegate = self
                }
            }
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            session.confirmQuit(store: store)
        }
    }
}
