import SwiftUI

struct MenuBarPopoverView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var sidebarVisibility: SidebarVisibilityStore
    @EnvironmentObject private var mainSectionVisibility: MainSectionVisibilityStore
    @EnvironmentObject private var mainWindowFullscreen: MainWindowFullscreenTracker
    @Environment(\.openWindow) private var openWindow
    @Environment(\.textZoom) private var textZoom

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle()
                .fill(CyberpunkTheme.neonCyan)
                .frame(height: 1)
                .shadow(color: CyberpunkTheme.neonCyan.opacity(0.45), radius: 3)
            TodoListContent(todos: store.todos, compact: true) { todo in
                store.selectedTodoID = todo.id
                openWindow(id: "main")
            }
            .frame(maxHeight: 360)
            Rectangle()
                .fill(CyberpunkTheme.rowDivider)
                .frame(height: 1)
            footer
        }
        .frame(width: 380)
        .background {
            SmokedGlassFill(material: .hudWindow, smokeOpacity: 0.38)
        }
        .background(PopoverWindowTranslucencyConfigurator())
        .overlay {
            Rectangle()
                .stroke(CyberpunkTheme.neonCyan, lineWidth: 1)
                .shadow(color: CyberpunkTheme.neonCyan.opacity(0.55), radius: 7)
        }
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
        .background(Color.black.opacity(0.18))
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    store.addTodo()
                    openWindow(id: "main")
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

            HStack {
                Button {
                    sidebarVisibility.toggle()
                    openWindow(id: "main")
                } label: {
                    Label(
                        sidebarVisibility.isVisible ? "Hide Sidebar" : "Show Sidebar",
                        systemImage: "sidebar.leading"
                    )
                }
                .buttonStyle(CyberBorderedButtonStyle())
                .help("Toggle main window todo list (⌘⌥S)")

                Button {
                    mainSectionVisibility.toggle()
                    openWindow(id: "main")
                } label: {
                    Label(
                        mainSectionVisibility.isVisible ? "Hide Editor" : "Show Editor",
                        systemImage: "sidebar.trailing"
                    )
                }
                .buttonStyle(CyberBorderedButtonStyle())
                .help("Toggle main window editor (⌘⌥E)")

                Button {
                    mainWindowFullscreen.toggle()
                    openWindow(id: "main")
                } label: {
                    Label(
                        mainWindowFullscreen.toggleMenuTitle,
                        systemImage: "arrow.up.left.and.arrow.down.right"
                    )
                }
                .buttonStyle(CyberBorderedButtonStyle())
                .help("Toggle main window full screen (⌃⌘F)")

                Spacer()
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.18))
    }
}
