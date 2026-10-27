import SwiftUI

private enum TodoListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"

    var id: String { rawValue }
}

private enum NoteTagFilterOption: Hashable, Identifiable {
    case all
    case tag(AkashicTag)

    var id: String {
        switch self {
        case .all: "__all__"
        case .tag(let tag): tag.nameKey
        }
    }

    var label: String {
        switch self {
        case .all: "All tags"
        case .tag(let tag): tag.name
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var editorSession: TodoEditorSession
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var noteEditorSession: NoteEditorSession
    @EnvironmentObject private var sidebarVisibility: SidebarVisibilityStore
    @EnvironmentObject private var mainSectionVisibility: MainSectionVisibilityStore
    @Environment(\.textZoom) private var textZoom

    @State private var workspaceTab: MainAppTab = .todos
    @State private var listFilter: TodoListFilter = .all
    @State private var noteSort: NoteListSort = .updatedNewest
    @State private var noteTagFilter: NoteTagFilterOption = .all

    private var filteredTodos: [TodoItem] {
        switch listFilter {
        case .all: store.todos
        case .active: store.todos.filter { !$0.completed }
        case .completed: store.todos.filter(\.completed)
        }
    }

    private var noteTagFilterOptions: [NoteTagFilterOption] {
        [.all] + noteStore.tagsUsedInNotes().map { .tag($0) }
    }

    private var filteredNotes: [NoteItem] {
        let tag: AkashicTag? = {
            if case .tag(let t) = noteTagFilter { return t }
            return nil
        }()
        return noteStore.filteredNotes(tag: tag, sort: noteSort)
    }

    var body: some View {
        VStack(spacing: 0) {
            MainWorkspaceTabBar(selection: $workspaceTab, onSelect: attemptSwitchTab)
            CyberHeaderStrip {
                headerActions
            }
            workspaceContent
        }
        .overlay {
            BorderCelebrationOverlay(
                completionCelebrationID: store.completionCelebrationID,
                deletionCelebrationID: store.deletionCelebrationID,
                noteCompletionCelebrationID: noteStore.completionCelebrationID,
                noteDeletionCelebrationID: noteStore.deletionCelebrationID
            )
        }
        .frame(minWidth: 820, minHeight: 520)
        .background(MainWindowChromeConfigurator())
        .background(
            WindowUnsavedChangesGuard(
                workspaceTab: workspaceTab,
                todoSession: editorSession,
                todoStore: store,
                noteSession: noteEditorSession,
                noteStore: noteStore
            )
        )
        .neonWindowFrame()
        .toolbar(.hidden, for: .windowToolbar)
        .toolbar(removing: .sidebarToggle)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .tint(CyberpunkTheme.neonCyan)
        .onChange(of: store.selectedTodoID) { _, newID in
            editorSession.syncToSelection(store: store, selectedID: newID)
        }
        .onChange(of: noteStore.selectedNoteID) { _, newID in
            noteEditorSession.syncToSelection(store: noteStore, selectedID: newID)
        }
        .onAppear {
            editorSession.syncToSelection(store: store, selectedID: store.selectedTodoID)
            noteEditorSession.syncToSelection(store: noteStore, selectedID: noteStore.selectedNoteID)
            AkashicAPIBootstrap.startIfNeeded(todoStore: store, noteStore: noteStore)
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspaceTab {
        case .todos:
            todoWorkspace
        case .notes:
            notesWorkspace
        }
    }

    private var showsMatrixRain: Bool {
        !sidebarVisibility.isVisible && !mainSectionVisibility.isVisible
    }

    private var sidebarExpandsToFill: Bool {
        sidebarVisibility.isVisible && !mainSectionVisibility.isVisible
    }

    @ViewBuilder
    private var todoWorkspace: some View {
        if showsMatrixRain {
            MatrixDigitalRainView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                if sidebarVisibility.isVisible {
                    todoListColumn
                }
                if mainSectionVisibility.isVisible {
                    TodoEditorView(session: editorSession)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var notesWorkspace: some View {
        if showsMatrixRain {
            MatrixDigitalRainView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                if sidebarVisibility.isVisible {
                    noteListColumn
                }
                if mainSectionVisibility.isVisible {
                    NoteEditorView(session: noteEditorSession)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private var todoListColumn: some View {
        let list = VStack(spacing: 0) {
            todoFilterStrip
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
    private var noteListColumn: some View {
        let list = VStack(spacing: 0) {
            noteFilterStrip
            NoteListContent(notes: filteredNotes, onSelect: { note in
                _ = noteEditorSession.selectNote(note, store: noteStore)
            }, onRecolorTag: applyTagRecolor)
        }
        if sidebarExpandsToFill {
            list.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list.frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            Button {
                switch workspaceTab {
                case .todos:
                    _ = editorSession.beginNewTodo(store: store)
                case .notes:
                    _ = noteEditorSession.beginNewNote(store: noteStore)
                }
            } label: {
                Image(systemName: "plus")
                    .imageScale(.medium)
            }
            .help(workspaceTab == .todos ? "New todo" : "New note")
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
                guard resolveUnsavedForActiveTab() else { return }
                mainSectionVisibility.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
                    .imageScale(.medium)
            }
            .help(mainSectionVisibility.headerTooltip)
            .buttonStyle(CyberHeaderIconButtonStyle())
        }
    }

    private var todoFilterStrip: some View {
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
            Rectangle().fill(CyberpunkTheme.rowDivider).frame(height: 1)
        }
    }

    private var noteFilterStrip: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(AkashicFont.mono(AkashicFont.caption, weight: .bold, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.neonCyan)
            ThemedDropdown(
                accessibilityTitle: "Filter by tag",
                selection: $noteTagFilter,
                options: noteTagFilterOptions,
                label: { $0.label },
                accent: { option in
                    if case .tag(let tag) = option { tag.color.swiftUIColor }
                    else { CyberpunkTheme.neonCyan }
                }
            )
            ThemedDropdown(
                accessibilityTitle: "Sort notes",
                selection: $noteSort,
                options: Array(NoteListSort.allCases),
                label: { $0.rawValue }
            )
            if case .tag(let tag) = noteTagFilter {
                NoteTagChip(tag: tag, onRecolor: { color in
                    applyTagRecolor(tag, color)
                })
            }
            Spacer()
            Button("New Note") {
                _ = noteEditorSession.beginNewNote(store: noteStore)
            }
            .buttonStyle(CyberBorderedButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle().fill(CyberpunkTheme.rowDivider).frame(height: 1)
        }
    }

    private func attemptSwitchTab(to tab: MainAppTab) -> Bool {
        guard tab != workspaceTab else { return true }
        switch workspaceTab {
        case .todos:
            guard editorSession.resolveUnsavedChanges(store: store) else { return false }
        case .notes:
            guard noteEditorSession.resolveUnsavedChanges(store: noteStore) else { return false }
        }
        return true
    }

    private func resolveUnsavedForActiveTab() -> Bool {
        switch workspaceTab {
        case .todos:
            editorSession.resolveUnsavedChanges(store: store)
        case .notes:
            noteEditorSession.resolveUnsavedChanges(store: noteStore)
        }
    }

    private func applyTagRecolor(_ tag: AkashicTag, color: AkashicTagColor) {
        _ = noteStore.setTagColor(name: tag.name, color: color)
        noteEditorSession.mutateForm { form in
            if form.draft.tags.contains(where: { $0.nameKey == tag.nameKey }) {
                form.refreshTagColors(from: noteStore.notes.first { $0.id == form.draft.id } ?? form.draft)
            }
        }
    }
}

private struct WindowUnsavedChangesGuard: NSViewRepresentable {
    let workspaceTab: MainAppTab
    let todoSession: TodoEditorSession
    let todoStore: TodoStore
    let noteSession: NoteEditorSession
    let noteStore: NoteStore

    func makeCoordinator() -> Coordinator {
        Coordinator(
            workspaceTab: workspaceTab,
            todoSession: todoSession,
            todoStore: todoStore,
            noteSession: noteSession,
            noteStore: noteStore
        )
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.workspaceTab = workspaceTab
        context.coordinator.todoSession = todoSession
        context.coordinator.todoStore = todoStore
        context.coordinator.noteSession = noteSession
        context.coordinator.noteStore = noteStore
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var workspaceTab: MainAppTab
        var todoSession: TodoEditorSession
        var todoStore: TodoStore
        var noteSession: NoteEditorSession
        var noteStore: NoteStore
        private weak var window: NSWindow?

        init(
            workspaceTab: MainAppTab,
            todoSession: TodoEditorSession,
            todoStore: TodoStore,
            noteSession: NoteEditorSession,
            noteStore: NoteStore
        ) {
            self.workspaceTab = workspaceTab
            self.todoSession = todoSession
            self.todoStore = todoStore
            self.noteSession = noteSession
            self.noteStore = noteStore
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
            todoSession.confirmQuit(store: todoStore) && noteSession.confirmQuit(store: noteStore)
        }
    }
}
