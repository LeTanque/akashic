import SwiftUI
import AppKit

@main
struct AkashicApp: App {
    @StateObject private var store = TodoStore()
    @StateObject private var editorSession = TodoEditorSession()
    @StateObject private var textZoom = TextZoomStore()
    @StateObject private var sidebarVisibility = SidebarVisibilityStore()
    @StateObject private var mainSectionVisibility = MainSectionVisibilityStore()
    @StateObject private var settings = AkashicSettingsStore()
    @NSApplicationDelegateAdaptor(AkashicAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(store)
                .environmentObject(editorSession)
                .environmentObject(sidebarVisibility)
                .environmentObject(mainSectionVisibility)
                .environmentObject(settings)
                .background(AppDelegateBinding(
                    store: store,
                    editorSession: editorSession,
                    settings: settings,
                    appDelegate: appDelegate
                ))
        } label: {
            Label("Akashic", systemImage: settings.menuBarSymbolName)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            appMenuCommands
            viewCommands
        }

        Window("Akashic", id: "main") {
            MainWindowView()
                .environmentObject(store)
                .environmentObject(editorSession)
                .environmentObject(textZoom)
                .environmentObject(sidebarVisibility)
                .environmentObject(mainSectionVisibility)
                .environmentObject(settings)
                .akashicTextZoom(textZoom)
                .background(LaunchOpenMainWindow())
                .background(AppDelegateBinding(
                    store: store,
                    editorSession: editorSession,
                    settings: settings,
                    appDelegate: appDelegate
                ))
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 920, height: 620)
        .defaultLaunchBehavior(.presented)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Todo") {
                    _ = editorSession.beginNewTodo(store: store)
                    NotificationCenter.default.post(name: .akashicOpenMainWindow, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("Save Todo") {
                    _ = editorSession.save(store: store)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!editorSession.form.canSave)
            }
            appMenuCommands
            viewCommands
        }
    }

    @CommandsBuilder
    private var appMenuCommands: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NotificationCenter.default.post(name: .akashicOpenSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }

    @CommandsBuilder
    private var viewCommands: some Commands {
        CommandMenu("View") {
            Button(sidebarVisibility.toggleMenuTitle) {
                sidebarVisibility.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(mainSectionVisibility.toggleMenuTitle) {
                mainSectionVisibility.toggle()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])

            Divider()

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

/// Ensures `openWindow` runs for launch/reopen notifications once the main window scene is mounted.
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

@MainActor
final class AkashicAppDelegate: NSObject, NSApplicationDelegate {
    private let settingsController = AkashicSettingsWindowController()
    private var openSettingsObserver: NSObjectProtocol?
    private weak var store: TodoStore?
    private weak var editorSession: TodoEditorSession?

    func bind(store: TodoStore, editorSession: TodoEditorSession, settings: AkashicSettingsStore) {
        self.store = store
        self.editorSession = editorSession
        settingsController.configure(store: store, settings: settings)
        settings.applyActivationPolicyAtLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        openSettingsObserver = NotificationCenter.default.addObserver(
            forName: .akashicOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.settingsController.showSettings()
            }
        }

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, let editorSession else { return .terminateNow }
        return editorSession.confirmQuit(store: store) ? .terminateNow : .terminateCancel
    }
}

private struct AppDelegateBinding: View {
    let store: TodoStore
    let editorSession: TodoEditorSession
    let settings: AkashicSettingsStore
    let appDelegate: AkashicAppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate.bind(store: store, editorSession: editorSession, settings: settings)
            }
    }
}
