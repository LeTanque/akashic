import SwiftUI
import AppKit

@main
struct AkashicApp: App {
    @StateObject private var root = AkashicRootModel()
    @NSApplicationDelegateAdaptor(AkashicAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(root)
                .background(AppDelegateBinding(root: root, appDelegate: appDelegate))
        } label: {
            Label("Akashic", systemImage: root.settings.menuBarSymbolName)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            appMenuCommands
            viewCommands
        }

        Window("Akashic", id: "main") {
            AkashicVaultRootView(root: root)
                .background(LaunchOpenMainWindow())
                .background(AppDelegateBinding(root: root, appDelegate: appDelegate))
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
                    guard let store = root.vault.todoStore else { return }
                    _ = root.editorSession.beginNewTodo(store: store)
                    NotificationCenter.default.post(name: .akashicOpenMainWindow, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(root.vault.presentation != .ready)
            }
            CommandGroup(after: .saveItem) {
                Button("Save Todo") {
                    guard let store = root.vault.todoStore else { return }
                    _ = root.editorSession.save(store: store)
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(root.vault.presentation != .ready || !root.editorSession.form.canSave)
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
            Button(root.sidebarVisibility.toggleMenuTitle) {
                root.sidebarVisibility.toggle()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button(root.mainSectionVisibility.toggleMenuTitle) {
                root.mainSectionVisibility.toggle()
            }
            .keyboardShortcut("e", modifiers: [.command, .option])

            Divider()

            Button("Zoom In") { root.textZoom.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(!root.textZoom.canZoomIn)
            Button("Zoom Out") { root.textZoom.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!root.textZoom.canZoomOut)
            Button("Actual Size") { root.textZoom.reset() }
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
    static let akashicRequestLock = Notification.Name("akashic.requestLock")
}

@MainActor
final class AkashicAppDelegate: NSObject, NSApplicationDelegate {
    private let settingsController = AkashicSettingsWindowController()
    private var openSettingsObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    private weak var root: AkashicRootModel?

    func bind(root: AkashicRootModel) {
        self.root = root
        settingsController.configure(root: root)
        root.settings.applyActivationPolicyAtLaunch()
        root.vault.start()
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

        lockObserver = NotificationCenter.default.addObserver(
            forName: .akashicRequestLock,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleLockRequest()
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
        guard let root else { return .terminateNow }
        guard let store = root.vault.todoStore, let noteStore = root.vault.noteStore else { return .terminateNow }
        guard root.editorSession.confirmQuit(store: store) else { return .terminateCancel }
        return root.noteEditorSession.confirmQuit(store: noteStore) ? .terminateNow : .terminateCancel
    }

    private func handleLockRequest() {
        guard let root else { return }
        guard root.vault.presentation == .ready else {
            root.vault.lock()
            return
        }
        guard let store = root.vault.todoStore, let noteStore = root.vault.noteStore else {
            root.vault.lock()
            return
        }
        let todoOK = root.editorSession.resolveUnsavedChanges(store: store)
        let noteOK = root.noteEditorSession.resolveUnsavedChanges(store: noteStore)
        if todoOK, noteOK {
            root.vault.lock()
        }
    }
}

private struct AppDelegateBinding: View {
    let root: AkashicRootModel
    let appDelegate: AkashicAppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate.bind(root: root)
            }
    }
}
