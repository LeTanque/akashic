import AppKit
import SwiftUI

extension Notification.Name {
    static let akashicOpenSettings = Notification.Name("akashic.openSettings")
}

@MainActor
final class AkashicSettingsWindowController: NSObject {
    private var panel: AkashicSettingsPanel?
    private weak var store: TodoStore?
    private weak var settings: AkashicSettingsStore?
    private var escapeMonitor: Any?

    func configure(store: TodoStore, settings: AkashicSettingsStore) {
        self.store = store
        self.settings = settings
    }

    func showSettings() {
        guard let store, let settings else { return }
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let size = AkashicSettingsChrome.initialSize(in: visible)
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )

        let root = AkashicSettingsView(onDone: { [weak self] in self?.dismiss() })
            .environmentObject(store)
            .environmentObject(settings)

        let newPanel = AkashicSettingsPanel(rootView: root, size: size, origin: origin)
        panel = newPanel
        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            guard let panel = self?.panel, panel.isKeyWindow else { return event }
            self?.dismiss()
            return nil
        }
    }

    func dismiss() {
        if let panel {
            AkashicSettingsChrome.remember(size: panel.frame.size)
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }
}

final class AkashicSettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(rootView: some View, size: NSSize, origin: NSPoint) {
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .normal
        collectionBehavior = [.canJoinAllSpaces]
        minSize = AkashicSettingsChrome.minimumSize

        let effect = AkashicSettingsChamferedEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true

        let tint = NSView(frame: effect.bounds)
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        tint.layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.55).cgColor
        effect.addSubview(tint)

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        contentView = effect
    }
}
