import AppKit
import Combine
import SwiftUI

/// Tracks and toggles native macOS full screen for the main Akashic window.
@MainActor
final class MainWindowFullscreenTracker: ObservableObject {
    @Published private(set) var isFullScreen = false

    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.willEnterFullScreenNotification,
            NSWindow.willExitFullScreenNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
        ]
        for name in names {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    Task { @MainActor in
                        self?.refresh(anchoredTo: notification.object as? NSWindow)
                    }
                }
            )
        }
        refresh(anchoredTo: MainWindowLocator.akashicMainWindow())
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func toggle() {
        MainWindowLocator.akashicMainWindow()?.toggleFullScreen(nil)
    }

    var toggleMenuTitle: String {
        isFullScreen ? "Exit Full Screen" : "Enter Full Screen"
    }

    var headerTooltip: String {
        isFullScreen ? "Exit full screen (⌃⌘F)" : "Enter full screen (⌃⌘F)"
    }

    private func refresh(anchoredTo window: NSWindow?) {
        if let window, window.title == "Akashic" {
            isFullScreen = window.styleMask.contains(.fullScreen)
            return
        }
        isFullScreen = MainWindowLocator.akashicMainWindow()?.styleMask.contains(.fullScreen) ?? false
    }
}

enum MainWindowLocator {
    static func akashicMainWindow() -> NSWindow? {
        if let key = NSApp.keyWindow, key.title == "Akashic" {
            return key
        }
        if let main = NSApp.mainWindow, main.title == "Akashic" {
            return main
        }
        return NSApp.windows.first { $0.title == "Akashic" }
    }
}
