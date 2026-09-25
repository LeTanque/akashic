import SwiftUI

@main
struct AkashicApp: App {
    @StateObject private var store = TodoStore()

    var body: some Scene {
        MenuBarExtra("Akashic", systemImage: "sparkles") {
            MenuBarPopoverView()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Window("Akashic", id: "main") {
            MainWindowView()
                .environmentObject(store)
        }
        .defaultSize(width: 920, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Todo") { store.addTodo() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}
