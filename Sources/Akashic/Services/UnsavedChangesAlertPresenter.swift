import AppKit
import SwiftUI

@MainActor
protocol UnsavedChangesAlertPresenting {
    func present(todoDisplayName: String) -> UnsavedChangesChoice
}

@MainActor
struct UnsavedChangesAlertPresenter: UnsavedChangesAlertPresenting {
    static func present(todoDisplayName: String) -> UnsavedChangesChoice {
        UnsavedChangesAlertPresenter().present(todoDisplayName: todoDisplayName)
    }

    func present(todoDisplayName: String) -> UnsavedChangesChoice {
        let state = ModalChoiceState()
        let panelSize = NSSize(width: 440, height: 210)
        let origin = Self.panelOrigin(for: panelSize)

        let root = UnsavedChangesAlertView(todoDisplayName: todoDisplayName) { choice in
            state.choice = choice
            NSApp.stopModal(withCode: .OK)
        }

        let panel = UnsavedChangesAlertPanel(rootView: root, size: panelSize, origin: origin)
        state.panel = panel

        let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard panel.isKeyWindow else { return event }
            if event.keyCode == 53 {
                state.choice = .cancel
                NSApp.stopModal(withCode: .OK)
                return nil
            }
            return event
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)

        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        panel.orderOut(nil)
        Self.refrontMainWindow()
        return state.choice
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

@MainActor
private final class ModalChoiceState {
    var choice: UnsavedChangesChoice = .cancel
    weak var panel: UnsavedChangesAlertPanel?
}

private final class UnsavedChangesAlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(rootView: some View, size: NSSize, origin: NSPoint) {
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

private struct UnsavedChangesAlertView: View {
    let todoDisplayName: String
    let onChoice: (UnsavedChangesChoice) -> Void

    @FocusState private var focusedAction: AlertAction?

    private enum AlertAction: Hashable {
        case save
        case discard
        case cancel
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            messageBlock
            Spacer(minLength: 0)
            buttonRow
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.12))
        .overlay {
            AkashicChamferedOutline(chamfer: AkashicSettingsChrome.windowChamfer)
                .stroke(AkashicSettingsChrome.accent.opacity(0.85), lineWidth: 1.5)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            focusedAction = .save
        }
    }

    private var header: some View {
        HStack {
            Text("UNSAVED CHANGES")
                .font(AkashicSettingsChrome.font(13, bold: true))
                .tracking(1.4)
                .foregroundStyle(Color.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.35))
    }

    private var messageBlock: some View {
        Text("Save your changes to \"\(todoDisplayName)\" before continuing?")
            .font(AkashicSettingsChrome.font(11))
            .foregroundStyle(AkashicSettingsChrome.label)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private var buttonRow: some View {
        HStack(spacing: 10) {
            Spacer()
            UnsavedChangesThemedButton(
                title: "CANCEL",
                accent: AkashicSettingsChrome.label,
                action: { onChoice(.cancel) }
            )
            .focused($focusedAction, equals: .cancel)
            .akashicSettingsFocusRing()
            .keyboardShortcut(.cancelAction)

            UnsavedChangesThemedButton(
                title: "DISCARD",
                accent: CyberpunkTheme.neonOrange,
                action: { onChoice(.discard) }
            )
            .focused($focusedAction, equals: .discard)
            .akashicSettingsFocusRing()

            UnsavedChangesThemedButton(
                title: "SAVE",
                accent: AkashicSettingsChrome.accent,
                action: { onChoice(.save) }
            )
            .focused($focusedAction, equals: .save)
            .akashicSettingsFocusRing()
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var footer: some View {
        HStack {
            Text("RETURN TO SAVE  ·  ESC TO CANCEL  ·  TAB TO MOVE")
                .font(AkashicSettingsChrome.font(9))
                .foregroundStyle(AkashicSettingsChrome.label)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35))
    }
}

private struct UnsavedChangesThemedButton: View {
    let title: String
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AkashicSettingsChrome.font(11, bold: true))
                .foregroundStyle(accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Rectangle().fill(Color.black.opacity(hovering ? 0.5 : 0.35)))
                .overlay(
                    Rectangle()
                        .stroke(accent.opacity(hovering ? 1 : 0.55), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct AkashicChamferedOutline: Shape {
    var chamfer: CGFloat

    func path(in rect: CGRect) -> Path {
        let cut = min(chamfer, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
