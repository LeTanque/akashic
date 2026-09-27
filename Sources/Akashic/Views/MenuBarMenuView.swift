import AppKit
import SwiftUI

/// Standard `MenuBarExtra` menu items (native NSMenu appearance, no custom popover chrome).
struct MenuBarMenuView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var sidebarVisibility: SidebarVisibilityStore
    @EnvironmentObject private var mainSectionVisibility: MainSectionVisibilityStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Akashic") {
            openMainWindow()
        }

        Button("New Todo") {
            store.addTodo()
            openMainWindow()
        }
        .keyboardShortcut("n", modifiers: .command)

        Divider()

        Button(sidebarVisibility.toggleMenuTitle) {
            sidebarVisibility.toggle()
            openMainWindow()
        }

        Button(mainSectionVisibility.toggleMenuTitle) {
            mainSectionVisibility.toggle()
            openMainWindow()
        }

        Divider()

        Button("Quit Akashic") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func openMainWindow() {
        if store.selectedTodoID == nil {
            store.selectedTodoID = store.todos.first?.id
        }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
