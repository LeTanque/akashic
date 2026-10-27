import AppKit
import SwiftUI

/// Standard `MenuBarExtra` menu items (native NSMenu appearance, no custom popover chrome).
struct MenuBarMenuView: View {
    @EnvironmentObject private var store: TodoStore
    @EnvironmentObject private var editorSession: TodoEditorSession
    @EnvironmentObject private var sidebarVisibility: SidebarVisibilityStore
    @EnvironmentObject private var mainSectionVisibility: MainSectionVisibilityStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Akashic") {
            openMainWindow()
        }

        Button("New Todo") {
            _ = editorSession.beginNewTodo(store: store)
            openMainWindow()
        }
        .keyboardShortcut("n", modifiers: .command)

        Divider()

        Button("Settings…") {
            NotificationCenter.default.post(name: .akashicOpenSettings, object: nil)
        }
        .keyboardShortcut(",", modifiers: .command)

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
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
