import AppKit
import SwiftUI

/// Cyberpunk-styled menu replacement (no native `Picker` / `NSPopUpButton` chrome).
struct ThemedDropdown<Value: Hashable>: View {
    @Environment(\.textZoom) private var textZoom

    var accessibilityTitle: String
    @Binding var selection: Value
    let options: [Value]
    var label: (Value) -> String
    var accent: (Value) -> Color = { _ in CyberpunkTheme.neonCyan }

    @State private var isOpen = false
    @State private var highlightedIndex: Int?
    @State private var isHovered = false

    private var selectedIndex: Int {
        options.firstIndex(where: { $0 == selection }) ?? 0
    }

    var body: some View {
        Button {
            isOpen.toggle()
            highlightedIndex = selectedIndex
        } label: {
            HStack(spacing: 6) {
                Text(label(selection))
                    .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                    .foregroundStyle(accent(selection))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CyberpunkTheme.neonCyan.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Rectangle().fill(Color.black.opacity(isHovered || isOpen ? 0.5 : 0.35)))
            .overlay(
                Rectangle()
                    .stroke(
                        CyberpunkTheme.neonCyan.opacity(isHovered || isOpen ? 1 : 0.55),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(accessibilityTitle)
        .background {
            BorderlessFloatingPanelAnchor(isPresented: $isOpen) {
                dropdownList
            }
        }
        .onChange(of: isOpen) { _, open in
            if open {
                highlightedIndex = selectedIndex
            }
        }
    }

    private var dropdownList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option == selection
                let highlighted = highlightedIndex == index
                Button {
                    selection = option
                    isOpen = false
                } label: {
                    HStack {
                        Text(label(option))
                            .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                            .foregroundStyle(accent(option))
                        Spacer()
                        if selected {
                            Text("▸")
                                .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                                .foregroundStyle(CyberpunkTheme.neonCyan)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Rectangle().fill(Color.black.opacity(highlighted ? 0.55 : 0.25)))
                    .overlay(
                        Rectangle()
                            .stroke(
                                CyberpunkTheme.neonCyan.opacity(highlighted ? 0.9 : 0.2),
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .focusEffectDisabled()
            }
        }
        .padding(6)
        .frame(minWidth: 160)
        .background(Color.black.opacity(0.92))
        .overlay(Rectangle().stroke(CyberpunkTheme.neonCyan.opacity(0.75), lineWidth: 1))
        .preferredColorScheme(.dark)
        .onAppear {
            highlightedIndex = selectedIndex
        }
        .background(
            ThemedDropdownKeyHandler(
                isActive: isOpen,
                optionCount: options.count,
                highlightedIndex: Binding(
                    get: { highlightedIndex ?? selectedIndex },
                    set: { highlightedIndex = $0 }
                ),
                onSelect: { index in
                    guard options.indices.contains(index) else { return }
                    selection = options[index]
                    isOpen = false
                },
                onDismiss: { isOpen = false }
            )
        )
    }
}

/// Arrow keys, Return, and Esc while the themed dropdown panel is open.
private struct ThemedDropdownKeyHandler: NSViewRepresentable {
    var isActive: Bool
    var optionCount: Int
    @Binding var highlightedIndex: Int
    var onSelect: (Int) -> Void
    var onDismiss: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.syncMonitor(active: isActive, view: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: ThemedDropdownKeyHandler
        private var monitor: Any?

        init(parent: ThemedDropdownKeyHandler) {
            self.parent = parent
        }

        func install(on view: NSView) {
            view.wantsLayer = true
        }

        func syncMonitor(active: Bool, view: NSView) {
            if active, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    return self.handle(event) ? nil : event
                }
            } else if !active {
                teardown()
            }
        }

        func teardown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard parent.isActive, parent.optionCount > 0 else { return false }
            switch event.keyCode {
            case 125: // down
                parent.highlightedIndex = min(parent.highlightedIndex + 1, parent.optionCount - 1)
                return true
            case 126: // up
                parent.highlightedIndex = max(parent.highlightedIndex - 1, 0)
                return true
            case 36, 76: // return, keypad enter
                parent.onSelect(parent.highlightedIndex)
                return true
            case 53: // esc
                parent.onDismiss()
                return true
            default:
                return false
            }
        }
    }
}
