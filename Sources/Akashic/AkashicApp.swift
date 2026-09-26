import SwiftUI
import AppKit

@main
struct AkashicApp: App {
    @StateObject private var store = TodoStore()
    @StateObject private var textZoom = TextZoomStore()
    @NSApplicationDelegateAdaptor(AkashicAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Akashic", systemImage: "sparkles") {
            MenuBarPopoverView()
                .environmentObject(store)
                .environmentObject(textZoom)
                .akashicTextZoom(textZoom)
                .background(LaunchOpenMainWindow())
        }
        .menuBarExtraStyle(.window)
        .commands { zoomCommands }

        Window("Akashic", id: "main") {
            MainWindowView()
                .environmentObject(store)
                .environmentObject(textZoom)
                .akashicTextZoom(textZoom)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 920, height: 620)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Todo") {
                    store.addTodo()
                    NotificationCenter.default.post(name: .akashicOpenMainWindow, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            zoomCommands
        }
    }

    @CommandsBuilder
    private var zoomCommands: some Commands {
        CommandMenu("View") {
            Button("Zoom In") { textZoom.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!textZoom.canZoomIn)
            Button("Zoom Out") { textZoom.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!textZoom.canZoomOut)
            Button("Actual Size") { textZoom.reset() }
                .keyboardShortcut("0", modifiers: .command)
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
