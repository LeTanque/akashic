import AppKit
import SwiftUI

/// Borderless popup anchored under a view (no arrow, no native popover chrome).
@MainActor
final class BorderlessFloatingPanelController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private weak var anchorView: NSView?
    var onDismiss: (() -> Void)?

    func present<Content: View>(
        anchor: NSView,
        @ViewBuilder content: () -> Content
    ) {
        anchorView = anchor
        let root = AnyView(content())
        if let panel, let hostingView {
            hostingView.rootView = root
            repositionPanel()
            return
        }

        let hosting = NSHostingView(rootView: root)
        hostingView = hosting

        let fitting = hosting.fittingSize
        let size = NSSize(
            width: max(fitting.width, 160),
            height: max(fitting.height, 40)
        )
        hosting.frame = NSRect(origin: .zero, size: size)

        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.level = .popUpMenu
        newPanel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        newPanel.isFloatingPanel = true
        newPanel.becomesKeyOnlyIfNeeded = true
        newPanel.hidesOnDeactivate = false
        newPanel.contentView = hosting
        panel = newPanel

        repositionPanel()
        newPanel.orderFront(nil)
        installOutsideClickMonitors()
    }

    func dismiss() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
        anchorView = nil
    }

    private func repositionPanel() {
        guard let panel, let anchorView, let window = anchorView.window else { return }
        let anchorInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorOnScreen = window.convertToScreen(anchorInWindow)
        let size = panel.frame.size
        var origin = NSPoint(
            x: anchorOnScreen.origin.x,
            y: anchorOnScreen.origin.y - size.height - 2
        )
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrameOrigin(origin)
    }

    private func installOutsideClickMonitors() {
        removeMonitors()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self else { return event }
            if self.shouldDismiss(for: event) {
                self.requestDismiss()
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            self?.requestDismiss()
        }
    }

    private func shouldDismiss(for event: NSEvent) -> Bool {
        guard panel != nil else { return false }
        let screenPoint = NSEvent.mouseLocation
        if let panel, panel.frame.contains(screenPoint) { return false }
        if let anchorView {
            let anchorFrame = anchorView.window?.convertToScreen(
                anchorView.convert(anchorView.bounds, to: nil)
            ) ?? .zero
            if anchorFrame.contains(screenPoint) { return false }
        }
        return true
    }

    private func requestDismiss() {
        onDismiss?()
        dismiss()
    }

    private func removeMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }
}

struct BorderlessFloatingPanelAnchor<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = $isPresented
        context.coordinator.panel.onDismiss = { [weak coordinator = context.coordinator] in
            coordinator?.isPresented.wrappedValue = false
        }
        if isPresented {
            context.coordinator.panel.present(anchor: nsView, content: content)
        } else {
            context.coordinator.panel.dismiss()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.panel.dismiss()
    }

    @MainActor
    final class Coordinator {
        var isPresented: Binding<Bool>
        let panel = BorderlessFloatingPanelController()

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }
    }
}
