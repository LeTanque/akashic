import AppKit
import ObjectiveC
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
        // SwiftUI re-injects titlebar/toolbar after the first attach.
        DispatchQueue.main.async { [weak self] in self?.stripNow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.stripNow()
        }
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
        applyWindowChrome(to: window)
        MainWindowSystemChromeCollapser.apply(to: window)
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

    /// Re-applied every pass: SwiftUI Window scenes restore titlebar chrome after first layout.
    private func applyWindowChrome(to window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.hasShadow = true
        window.contentView?.clipsToBounds = false
        window.toolbar = nil
        window.setAutorecalculatesContentBorderThickness(false, for: .maxY)
        window.setContentBorderThickness(0, for: .maxY)

        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(kind) {
                button.isHidden = true
                button.alphaValue = 0
            }
        }

        while !window.titlebarAccessoryViewControllers.isEmpty {
            window.removeTitlebarAccessoryViewController(at: 0)
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
    static var observedWindows = Set<ObjectIdentifier>()
}

/// Leftover vertical gap from the system titlebar / `contentLayoutRect`, not neon insets.
enum MainWindowTitlebarMetrics {
    /// Points reserved above the unobscured content layout inside `contentView`.
    static func reservedTop(contentBounds: CGRect, contentLayoutInContentView: CGRect) -> CGFloat {
        max(0, contentBounds.maxY - contentLayoutInContentView.maxY)
    }

    static func reservedTop(in window: NSWindow) -> CGFloat {
        guard let contentView = window.contentView else {
            return max(0, window.frame.height - window.contentLayoutRect.height)
        }
        let layout = contentView.convert(window.contentLayoutRect, from: nil)
        return reservedTop(contentBounds: contentView.bounds, contentLayoutInContentView: layout)
    }
}

/// Hide the titlebar container and zero SwiftUI hosting safe-area so content sits
/// on the neon content inset, not an extra system titlebar band.
enum MainWindowSystemChromeCollapser {
    static func apply(to window: NSWindow) {
        collapseTitlebarViews(in: window.contentView?.superview)
        collapseTitlebarViews(in: window.contentView)
        neutralizeHostingSafeArea(in: window.contentView)
        neutralizeHostingSafeArea(in: window.contentView?.superview)
        if let contentView = window.contentView {
            cancelRemainingTopSafeArea(contentView)
        }
    }

    private static func collapseTitlebarViews(in root: NSView?) {
        guard let root else { return }
        let name = String(describing: type(of: root))
        if isTitlebarChrome(name) {
            root.isHidden = true
            root.alphaValue = 0
            if root.frame.height > 0.5 {
                root.setFrameSize(NSSize(width: root.frame.width, height: 0))
            }
        }
        for child in root.subviews {
            collapseTitlebarViews(in: child)
        }
    }

    private static func isTitlebarChrome(_ typeName: String) -> Bool {
        typeName.contains("NSTitlebarContainerView")
            || typeName.contains("NSTitlebarView")
            || typeName.contains("NSTitlebarAccessoryClipView")
            || typeName.contains("NSToolbarTitlebar")
    }

    private static func neutralizeHostingSafeArea(in root: NSView?) {
        guard let root else { return }
        if hostingViewClearsSafeArea(root) {
            setSafeAreaRegionsEmpty(root)
            cancelRemainingTopSafeArea(root)
        }
        for child in root.subviews {
            neutralizeHostingSafeArea(in: child)
        }
    }

    private static func hostingViewClearsSafeArea(_ view: NSView) -> Bool {
        view.responds(to: NSSelectorFromString("setSafeAreaRegions:"))
    }

    /// `NSHostingView.safeAreaRegions = []` so the titlebar is not a SwiftUI inset.
    private static func setSafeAreaRegionsEmpty(_ view: NSView) {
        let selector = NSSelectorFromString("setSafeAreaRegions:")
        guard view.responds(to: selector),
              let method = class_getInstanceMethod(object_getClass(view), selector)
        else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
        setter(view, selector, 0)
    }

    /// If `contentLayoutRect` still reports a titlebar band, cancel it with
    /// `additionalSafeAreaInsets` so SwiftUI does not pad the header down.
    private static func cancelRemainingTopSafeArea(_ view: NSView) {
        let systemTop = view.safeAreaInsets.top - view.additionalSafeAreaInsets.top
        let target = systemTop > 0.5 ? -systemTop : 0
        guard abs(view.additionalSafeAreaInsets.top - target) > 0.5 else { return }
        var insets = view.additionalSafeAreaInsets
        insets.top = target
        view.additionalSafeAreaInsets = insets
    }
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
