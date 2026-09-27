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

        Button("Import Demo Seed…") {
            importBundledSeedFromMenu()
        }

        Button("Import JSON…") {
            importJSONFromMenu()
        }

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

    private func importBundledSeedFromMenu() {
        guard AkashicImportConfirmations.confirmReplaceWithBundledSeed() == .confirmed else { return }
        store.importSeedFromBundle(replaceExisting: true)
    }

    private func importJSONFromMenu() {
        guard AkashicImportConfirmations.confirmReplaceWithJSONFile() == .confirmed else { return }
        guard let url = AkashicJSONImportPanel.pickFileURL() else { return }
        store.importSeedFromFile(url: url)
    }

    private func openMainWindow() {
        if store.selectedTodoID == nil {
            store.selectedTodoID = store.todos.first?.id
        }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
