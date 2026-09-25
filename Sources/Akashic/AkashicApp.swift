import SwiftUI
import AppKit

@main
struct AkashicApp: App {
    @StateObject private var store = TodoStore()
    @NSApplicationDelegateAdaptor(AkashicAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Akashic", systemImage: "sparkles") {
            MenuBarPopoverView()
                .environmentObject(store)
                .background(LaunchOpenMainWindow())
        }
        .menuBarExtraStyle(.window)

        Window("Akashic", id: "main") {
            MainWindowView()
                .environmentObject(store)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 920, height: 620)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Todo") { store.addTodo() }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
    }
}

/// Lives in MenuBarExtra so openWindow is available even before the Window scene mounts.
private struct LaunchOpenMainWindow: View {
    @Environment(\.openWindow) private var openWindow
    @State private var didOpen = false

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: openOnce)
            .onReceive(NotificationCenter.default.publisher(for: .akashicOpenMainWindow)) { _ in
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
    }

    private func openOnce() {
        guard !didOpen else { return }
        didOpen = true
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name {
    static let akashicOpenMainWindow = Notification.Name("akashic.openMainWindow")
}

final class AkashicAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NotificationCenter.default.post(name: .akashicOpenMainWindow, object: nil)
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeKey {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .akashicOpenMainWindow, object: nil)
        return true
    }
}
