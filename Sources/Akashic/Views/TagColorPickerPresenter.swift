import AppKit
import SwiftUI

@MainActor
protocol TagColorPickerPresenting {
    func pickColor(for tag: AkashicTag, anchorOnScreen: NSRect) -> AkashicTagColor?
}

/// Themed tag-color palette for right-click on a tag chip.
///
/// Built from AppKit controls (like `UnsavedChangesAlertPresenter`) because the picker is
/// opened synchronously from a SwiftUI context-menu path; SwiftUI buttons in a nested modal panel
/// do not receive clicks reliably. Uses a non-modal panel plus event monitors for outside click
/// and Esc instead of wedging the app in `runModal`.
@MainActor
struct TagColorPickerPresenter: TagColorPickerPresenting {
    static var defaultPanelSize: NSSize {
        let rows = (AkashicTagColor.allCases.count + 4) / 5
        return NSSize(width: 220, height: 56 + CGFloat(rows) * 36)
    }

    static func pickColor(for tag: AkashicTag, anchor: NSRect) -> AkashicTagColor? {
        TagColorPickerPresenter().pickColor(for: tag, anchorOnScreen: anchor)
    }

    func pickColor(for tag: AkashicTag, anchorOnScreen: NSRect) -> AkashicTagColor? {
        let session = TagColorPickerSession(selected: tag.color)
        let panelSize = Self.defaultPanelSize
        let origin = Self.panelOrigin(anchorOnScreen: anchorOnScreen, panelSize: panelSize)
        let panel = TagColorPickerPanel(
            selected: tag.color,
            size: panelSize,
            origin: origin,
            session: session
        )
        session.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        session.installDismissMonitors()

        while session.outcome == nil {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }

        session.tearDown()
        panel.orderOut(nil)
        Self.refrontMainWindow()

        switch session.outcome {
        case .picked(let color):
            return color
        case .cancelled, .none:
            return nil
        }
    }

    static func panelOrigin(anchorOnScreen: NSRect, panelSize: NSSize) -> NSPoint {
        var origin = NSPoint(
            x: anchorOnScreen.midX - panelSize.width / 2,
            y: anchorOnScreen.minY - panelSize.height - 8
        )
        let visible = screenVisibleFrame(containing: anchorOnScreen)
        origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - panelSize.width - 8))
        origin.y = max(visible.minY + 8, min(origin.y, visible.maxY - panelSize.height - 8))
        return origin
    }

    static func screenVisibleFrame(containing anchor: NSRect) -> NSRect {
        if let match = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) {
            return match.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
    }

    private static func refrontMainWindow() {
        DispatchQueue.main.async {
            NSApp.windows
                .first { window in
                    window.isVisible && window.canBecomeKey && !(window is TagColorPickerPanel)
                }?
                .makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
private final class TagColorPickerSession {
    enum Outcome {
        case cancelled
        case picked(AkashicTagColor)
    }

    let selected: AkashicTagColor
    var outcome: Outcome?
    weak var panel: TagColorPickerPanel?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localKeyMonitor: Any?

    init(selected: AkashicTagColor) {
        self.selected = selected
    }

    func finish(with outcome: Outcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
    }

    func installDismissMonitors() {
        tearDownMonitors()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] event in
            guard let self, let panel = self.panel else { return event }
            let point = NSEvent.mouseLocation
            if !panel.frame.contains(point) {
                self.finish(with: .cancelled)
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            self?.finish(with: .cancelled)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Esc
                self.finish(with: .cancelled)
                return nil
            }
            return event
        }
    }

    func tearDown() {
        tearDownMonitors()
    }

    private func tearDownMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}

private enum TagColorPickerStyle {
    static let accent = NSColor(AkashicSettingsChrome.accent)
    static let label = NSColor(white: 0.56, alpha: 1)

    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let name = bold ? "Menlo-Bold" : "Menlo-Regular"
        return NSFont(name: name, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

private final class TagColorPickerPanel: NSPanel {
    private weak var session: TagColorPickerSession?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(selected: AkashicTagColor, size: NSSize, origin: NSPoint, session: TagColorPickerSession) {
        self.session = session
        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .popUpMenu
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let content = TagColorPickerContentView(frame: NSRect(origin: .zero, size: size))
        content.autoresizingMask = [.width, .height]
        buildContent(in: content, selected: selected, session: session)
        contentView = content
    }

    override func cancelOperation(_ sender: Any?) {
        session?.finish(with: .cancelled)
    }

    private func buildContent(
        in content: TagColorPickerContentView,
        selected: AkashicTagColor,
        session: TagColorPickerSession
    ) {
        let inset: CGFloat = 12
        let title = NSTextField(labelWithString: "TAG COLOR")
        title.font = TagColorPickerStyle.font(10, bold: true)
        title.textColor = TagColorPickerStyle.label
        title.frame = NSRect(x: inset, y: inset, width: content.bounds.width - inset * 2, height: 14)
        content.addSubview(title)

        let swatchSize: CGFloat = 28
        let spacing: CGFloat = 8
        let columns = 5
        var x = inset
        var y = inset + 22
        var column = 0
        for color in AkashicTagColor.allCases {
            let button = TagColorSwatchButton(color: color, selected: color == selected)
            button.frame = NSRect(x: x, y: y, width: swatchSize, height: swatchSize)
            button.onPick = { [weak session] picked in
                session?.finish(with: .picked(picked))
            }
            content.addSubview(button)
            column += 1
            if column >= columns {
                column = 0
                x = inset
                y += swatchSize + spacing
            } else {
                x += swatchSize + spacing
            }
        }

        let outline = TagColorPickerOutlineView(frame: content.bounds)
        outline.autoresizingMask = [.width, .height]
        content.addSubview(outline)
    }

}

private final class TagColorPickerContentView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.88).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class TagColorPickerOutlineView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        TagColorPickerStyle.accent.withAlphaComponent(0.75).setStroke()
        path.stroke()
    }
}

private final class TagColorSwatchButton: NSButton {
    private let swatchColor: AkashicTagColor
    private let isSelected: Bool
    private var hovering = false { didSet { needsDisplay = true } }
    var onPick: ((AkashicTagColor) -> Void)?

    init(color: AkashicTagColor, selected: Bool) {
        swatchColor = color
        isSelected = selected
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        title = ""
        toolTip = color.rawValue
        target = self
        action = #selector(clicked)
    }

    @objc private func clicked() {
        onPick?(swatchColor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 3
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset))
        NSColor(swatchColor.swiftUIColor).setFill()
        circle.fill()
        let stroke = NSColor.white.withAlphaComponent(isSelected || hovering ? 0.95 : 0.25)
        stroke.setStroke()
        circle.lineWidth = isSelected ? 2 : 1
        circle.stroke()
    }
}
