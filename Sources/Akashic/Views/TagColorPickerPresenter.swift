import AppKit
import SwiftUI

@MainActor
enum TagColorPickerPresenter {
    static func pickColor(for tag: AkashicTag, anchor: NSRect) -> AkashicTagColor? {
        let state = PickerState()
        let panelSize = NSSize(width: 220, height: 56 + CGFloat(AkashicTagColor.allCases.count / 5 + 1) * 36)
        var origin = NSPoint(x: anchor.midX - panelSize.width / 2, y: anchor.minY - panelSize.height - 8)
        if let screen = NSScreen.main?.visibleFrame {
            origin.x = max(screen.minX + 8, min(origin.x, screen.maxX - panelSize.width - 8))
            origin.y = max(screen.minY + 8, origin.y)
        }

        let root = TagColorPickerView(selected: tag.color) { choice in
            state.choice = choice
            NSApp.stopModal(withCode: .OK)
        }

        let panel = TagColorPickerPanel(rootView: root, size: panelSize, origin: origin)
        state.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        return state.choice
    }
}

@MainActor
private final class PickerState {
    var choice: AkashicTagColor?
    weak var panel: TagColorPickerPanel?
}

private final class TagColorPickerPanel: NSPanel {
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
        isReleasedWhenClosed = false
        level = .popUpMenu

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: size)
        contentView = hosting
    }
}

private struct TagColorPickerView: View {
    let selected: AkashicTagColor
    let onPick: (AkashicTagColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TAG COLOR")
                .font(AkashicSettingsChrome.font(10, bold: true))
                .foregroundStyle(AkashicSettingsChrome.label)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 5), spacing: 8) {
                ForEach(AkashicTagColor.allCases) { color in
                    Button {
                        onPick(color)
                    } label: {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(selected == color ? 0.95 : 0.25), lineWidth: selected == color ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.rawValue)
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.88))
        .overlay {
            Rectangle()
                .stroke(CyberpunkTheme.neonCyan.opacity(0.75), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
    }
}
