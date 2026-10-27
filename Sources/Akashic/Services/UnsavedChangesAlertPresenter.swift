import AppKit
import SwiftUI

@MainActor
protocol UnsavedChangesAlertPresenting {
    func present(todoDisplayName: String) -> UnsavedChangesChoice
}

/// Akashic-styled replacement for the old `NSAlert` unsaved-changes prompt.
///
/// The panel content is plain AppKit on purpose. The guard runs synchronously from inside
/// SwiftUI gesture/button actions (row click, New Todo), and a nested `runModal` started there
/// cannot deliver clicks or key shortcuts to SwiftUI views hosted in the modal panel; the panel
/// froze. AppKit controls (like `NSAlert`'s) keep working in that nested modal loop.
@MainActor
struct UnsavedChangesAlertPresenter: UnsavedChangesAlertPresenting {
    static func present(todoDisplayName: String) -> UnsavedChangesChoice {
        UnsavedChangesAlertPresenter().present(todoDisplayName: todoDisplayName)
    }

    func present(todoDisplayName: String) -> UnsavedChangesChoice {
        let panelSize = NSSize(width: 440, height: 210)
        let origin = Self.panelOrigin(for: panelSize)
        let panel = UnsavedChangesAlertPanel(
            todoDisplayName: todoDisplayName,
            size: panelSize,
            origin: origin
        )

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.saveButton)
        NSApp.runModal(for: panel)

        panel.orderOut(nil)
        Self.refrontMainWindow()
        return panel.choice
    }

    private static func panelOrigin(for size: NSSize) -> NSPoint {
        let reference = NSApp.mainWindow ?? NSApp.keyWindow
        if let reference {
            let frame = reference.frame
            return NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            )
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
    }

    private static func refrontMainWindow() {
        DispatchQueue.main.async {
            NSApp.windows
                .first { window in
                    window.isVisible && window.canBecomeKey && !(window is UnsavedChangesAlertPanel)
                }?
                .makeKeyAndOrderFront(nil)
        }
    }
}

private enum UnsavedAlertStyle {
    static let accent = NSColor(AkashicSettingsChrome.accent)
    static let label = NSColor(white: 0.56, alpha: 1)
    static let discard = NSColor(CyberpunkTheme.neonOrange)
    static let band = NSColor(calibratedWhite: 0, alpha: 0.35)

    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        let name = bold ? "Menlo-Bold" : "Menlo-Regular"
        return NSFont(name: name, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }
}

private final class UnsavedChangesAlertPanel: NSPanel {
    private(set) var choice: UnsavedChangesChoice = .cancel
    private(set) var saveButton: UnsavedAlertButton!

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(todoDisplayName: String, size: NSSize, origin: NSPoint) {
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
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        let effect = AkashicSettingsChamferedEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true

        let content = UnsavedAlertContentView(frame: effect.bounds)
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        contentView = effect

        buildContent(in: content, todoDisplayName: todoDisplayName)
    }

    private func buildContent(in content: NSView, todoDisplayName: String) {
        let width = content.bounds.width
        let height = content.bounds.height
        let inset: CGFloat = 16

        // Header band (content view is flipped: y grows downward).
        let header = UnsavedAlertBandView(frame: NSRect(x: 0, y: 0, width: width, height: 40))
        content.addSubview(header)
        let title = Self.label(
            "UNSAVED CHANGES",
            font: UnsavedAlertStyle.font(13, bold: true),
            color: .white,
            kern: 1.4
        )
        title.frame = NSRect(x: inset, y: 11, width: width - inset * 2 - 20, height: 18)
        header.addSubview(title)

        let message = Self.label(
            "Save your changes to \"\(todoDisplayName)\" before continuing?",
            font: UnsavedAlertStyle.font(11),
            color: UnsavedAlertStyle.label
        )
        message.maximumNumberOfLines = 3
        message.lineBreakMode = .byTruncatingTail
        message.cell?.wraps = true
        message.frame = NSRect(x: inset, y: 54, width: width - inset * 2, height: 46)
        content.addSubview(message)

        // Footer band.
        let footerHeight: CGFloat = 28
        let footer = UnsavedAlertBandView(
            frame: NSRect(x: 0, y: height - footerHeight, width: width, height: footerHeight)
        )
        content.addSubview(footer)
        let hint = Self.label(
            "RETURN TO SAVE  ·  ESC TO CANCEL  ·  TAB TO MOVE",
            font: UnsavedAlertStyle.font(9),
            color: UnsavedAlertStyle.label
        )
        hint.frame = NSRect(x: inset, y: 8, width: width - inset * 2, height: 13)
        footer.addSubview(hint)

        // Buttons, right-aligned: CANCEL  DISCARD  SAVE.
        let cancel = UnsavedAlertButton(title: "CANCEL", accent: UnsavedAlertStyle.label)
        let discard = UnsavedAlertButton(title: "DISCARD", accent: UnsavedAlertStyle.discard)
        let save = UnsavedAlertButton(title: "SAVE", accent: UnsavedAlertStyle.accent)
        cancel.keyEquivalent = "\u{1b}"
        save.keyEquivalent = "\r"
        cancel.target = self
        cancel.action = #selector(chooseCancel(_:))
        discard.target = self
        discard.action = #selector(chooseDiscard(_:))
        save.target = self
        save.action = #selector(chooseSave(_:))

        let buttonHeight: CGFloat = 26
        let buttonY = height - footerHeight - 10 - buttonHeight
        var x = width - inset
        for button in [save, discard, cancel] {
            let buttonWidth = button.intrinsicContentSize.width
            x -= buttonWidth
            button.frame = NSRect(x: x, y: buttonY, width: buttonWidth, height: buttonHeight)
            content.addSubview(button)
            x -= 10
        }
        cancel.nextKeyView = discard
        discard.nextKeyView = save
        save.nextKeyView = cancel
        initialFirstResponder = save
        saveButton = save

        let outline = UnsavedAlertOutlineView(frame: content.bounds)
        outline.autoresizingMask = [.width, .height]
        content.addSubview(outline)
    }

    private static func label(
        _ text: String,
        font: NSFont,
        color: NSColor,
        kern: CGFloat = 0
    ) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if kern != 0 { attributes[.kern] = kern }
        field.attributedStringValue = NSAttributedString(string: text, attributes: attributes)
        field.isSelectable = false
        return field
    }

    private func finish(with choice: UnsavedChangesChoice) {
        self.choice = choice
        NSApp.stopModal(withCode: .OK)
    }

    @objc private func chooseCancel(_ sender: Any?) { finish(with: .cancel) }
    @objc private func chooseDiscard(_ sender: Any?) { finish(with: .discard) }
    @objc private func chooseSave(_ sender: Any?) { finish(with: .save) }

    override func cancelOperation(_ sender: Any?) {
        finish(with: .cancel)
    }
}

/// Flipped container so layout reads top-down; tinted like the settings panel.
private final class UnsavedAlertContentView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.62).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class UnsavedAlertBandView: NSView {
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = UnsavedAlertStyle.band.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Cyan chamfered outline matching the settings window (cut at the top-right corner).
private final class UnsavedAlertOutlineView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let cut = min(AkashicSettingsChrome.windowChamfer, min(rect.width, rect.height) / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - cut, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + cut))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.close()
        path.lineWidth = 1.5
        UnsavedAlertStyle.accent.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}

/// Squared, outlined, monospaced button in the Akashic style. Always takes keyboard focus so
/// Tab moves between the three choices and Space activates the focused one.
private final class UnsavedAlertButton: NSButton {
    private let accent: NSColor
    private var hovering = false { didSet { updateAppearance() } }

    init(title: String, accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.borderWidth = 1
        focusRingType = .exterior
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: UnsavedAlertStyle.font(11, bold: true),
                .foregroundColor: accent,
            ]
        )
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let textWidth = attributedTitle.size().width
        return NSSize(width: ceil(textWidth) + 24, height: 26)
    }

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

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

    private func updateAppearance() {
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: hovering ? 0.5 : 0.35).cgColor
        layer?.borderColor = accent.withAlphaComponent(hovering ? 1 : 0.55).cgColor
    }
}
