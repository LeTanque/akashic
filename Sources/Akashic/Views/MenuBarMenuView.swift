import AppKit
import SwiftUI

/// Standard `MenuBarExtra` menu items (native NSMenu appearance, no custom popover chrome).
struct MenuBarMenuView: View {
    @EnvironmentObject private var root: AkashicRootModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Akashic") {
            openMainWindow()
        }

        Button("New Todo") {
            guard let store = root.vault.todoStore else {
                openMainWindow()
                return
            }
            _ = root.editorSession.beginNewTodo(store: store)
            openMainWindow()
        }
        .keyboardShortcut("n", modifiers: .command)
        .disabled(root.vault.presentation != .ready)

        Divider()

        Button("Lock Akashic") {
            NotificationCenter.default.post(name: .akashicRequestLock, object: nil)
        }
        .disabled(root.vault.presentation != .ready)

        Button("Settings…") {
            NotificationCenter.default.post(name: .akashicOpenSettings, object: nil)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(root.sidebarVisibility.toggleMenuTitle) {
            root.sidebarVisibility.toggle()
            openMainWindow()
        }

        Button(root.mainSectionVisibility.toggleMenuTitle) {
            root.mainSectionVisibility.toggle()
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
