import AppKit
import SwiftUI

/// Configures the main Akashic document window: no title bar, no traffic lights, clear/non-opaque fill so smoked glass can show.
struct MainWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> MainWindowChromeStripperView {
        MainWindowChromeStripperView()
    }

    func updateNSView(_ nsView: MainWindowChromeStripperView, context: Context) {
        nsView.stripNow()
    }
}

/// Runs on every layout pass so SwiftUI cannot re-inject a sidebar toggle into the titlebar.
final class MainWindowChromeStripperView: NSView {
    override var isHidden: Bool {
        get { true }
        set { _ = newValue }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stripNow()
        installWindowObserversIfNeeded()
    }

    override func layout() {
        super.layout()
        stripNow()
    }

    func stripNow() {
        guard let window, window.title == "Akashic" else { return }
        MainWindowSidebarToggleStripper.apply(to: window)
        applyTranslucentWindow(to: window)
        MainWindowOpaqueFillClearer.apply(to: window)
        applyOneTimeWindowChrome(to: window)
    }

    private func applyTranslucentWindow(to window: NSWindow) {
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.isOpaque = false
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func installWindowObserversIfNeeded() {
        guard let window, window.title == "Akashic" else { return }
        let token = ObjectIdentifier(window)
        guard !MainWindowChromeState.observedWindows.contains(token) else { return }
        MainWindowChromeState.observedWindows.insert(token)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.stripNow()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.stripNow()
        }
    }

    private func applyOneTimeWindowChrome(to window: NSWindow) {
        let token = ObjectIdentifier(window)
        guard !MainWindowChromeState.configured.contains(token) else { return }
        MainWindowChromeState.configured.insert(token)

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.contentView?.clipsToBounds = false

        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
    }
}

enum MainWindowOpaqueFillClearer {
    static func apply(to window: NSWindow) {
        clear(in: window.contentView)
        clear(in: window.contentView?.superview)
    }

    private static func clear(in root: NSView?) {
        guard let root else { return }
        if let split = root as? NSSplitView {
            split.wantsLayer = true
            split.layer?.isOpaque = false
            split.layer?.backgroundColor = NSColor.clear.cgColor
        }
        if let scroll = root as? NSScrollView {
            scroll.drawsBackground = false
            scroll.backgroundColor = .clear
        }
        if let clip = root as? NSClipView {
            clip.drawsBackground = false
            clip.backgroundColor = .clear
        }
        if let table = root as? NSTableView {
            table.backgroundColor = .clear
            table.enclosingScrollView?.drawsBackground = false
        }
        for subview in root.subviews {
            clear(in: subview)
        }
    }
}

enum MainWindowSidebarToggleStripper {
    private static let togglePhrases = [
        "hide sidebar",
        "show sidebar",
        "toggle sidebar",
    ]

    static func apply(to window: NSWindow) {
        window.toolbar = nil

        if let themeFrame = window.contentView?.superview {
            stripViews(in: themeFrame, matchAccessibility: true)
        }
        stripViews(in: window.contentView, matchAccessibility: false)
    }

    private static func stripViews(in root: NSView?, matchAccessibility: Bool) {
        guard let root else { return }
        for subview in root.subviews {
            if shouldRemove(subview, matchAccessibility: matchAccessibility) {
                subview.isHidden = true
                subview.alphaValue = 0
                subview.removeFromSuperview()
                continue
            }
            stripViews(in: subview, matchAccessibility: matchAccessibility)
        }
    }

    private static func shouldRemove(_ view: NSView, matchAccessibility: Bool) -> Bool {
        let className = String(describing: type(of: view)).lowercased()
        if className.contains("sidebartoggle") || className.contains("sidebartoolbar") {
            return true
        }
        if className.contains("sidebar") && (className.contains("toggle") || className.contains("button")) {
            return true
        }

        guard matchAccessibility else { return false }

        if let button = view as? NSButton {
            return matchesSidebarText(collectAccessibilityStrings(from: button))
        }

        return false
    }

    private static func collectAccessibilityStrings(from view: NSView) -> [String] {
        [
            view.accessibilityLabel(),
            view.accessibilityHelp(),
            view.accessibilityTitle(),
            view.toolTip,
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private static func matchesSidebarText(_ strings: [String]) -> Bool {
        for value in strings {
            let lower = value.lowercased()
            for phrase in togglePhrases where lower.contains(phrase) {
                return true
            }
        }
        return false
    }
}

private enum MainWindowChromeState {
    static var configured = Set<ObjectIdentifier>()
    static var observedWindows = Set<ObjectIdentifier>()
}

/// Drag the window from the header strip (`performDrag` on mouse down).
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

final class WindowDragNSView: NSView {
    override var isOpaque: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Makes a MenuBarExtra / popover window clear so `behindWindow` glass can show.
struct PopoverWindowTranslucencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> PopoverWindowTranslucencyView {
        PopoverWindowTranslucencyView()
    }

    func updateNSView(_ nsView: PopoverWindowTranslucencyView, context: Context) {
        nsView.apply()
    }
}

final class PopoverWindowTranslucencyView: NSView {
    override var isOpaque: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    override func layout() {
        super.layout()
        apply()
    }

    func apply() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        contentViewLayerIsTransparent(window)
        MainWindowOpaqueFillClearer.apply(to: window)
    }

    private func contentViewLayerIsTransparent(_ window: NSWindow) {
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.isOpaque = false
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
