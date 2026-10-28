import AppKit
import SwiftUI

struct NoteTagChipRow: View {
    @Environment(\.textZoom) private var textZoom
    let tags: [AkashicTag]
    var onRemove: ((AkashicTag) -> Void)?
    var onRecolor: (AkashicTag, AkashicTagColor) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags) { tag in
                NoteTagChip(
                    tag: tag,
                    onRemove: onRemove.map { remove in { remove(tag) } },
                    onRecolor: { color in onRecolor(tag, color) }
                )
            }
        }
    }
}

struct NoteTagChip: View {
    @Environment(\.textZoom) private var textZoom
    let tag: AkashicTag
    var onRemove: (() -> Void)?
    var onRecolor: (AkashicTagColor) -> Void

    var body: some View {
        TagChipRightClickHost(onRightClick: presentPicker) {
            HStack(spacing: 4) {
                Text(tag.name)
                    .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                    .foregroundStyle(tag.color.swiftUIColor)
                    .lineLimit(1)
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(tag.color.swiftUIColor.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove tag \(tag.name)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tag.color.swiftUIColor.opacity(0.12))
            .overlay(
                Rectangle()
                    .stroke(tag.color.swiftUIColor.opacity(0.75), lineWidth: 1)
            )
        }
        .accessibilityLabel("Tag \(tag.name)")
    }

    private func presentPicker(anchor: NSRect) {
        guard let picked = TagColorPickerPresenter.pickColor(for: tag, anchor: anchor) else { return }
        onRecolor(picked)
    }
}

private struct TagChipRightClickHost<Content: View>: NSViewRepresentable {
    let onRightClick: (NSRect) -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = RightClickHostingView(rootView: content())
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content()
        (nsView as? RightClickHostingView<Content>)?.onRightClick = onRightClick
    }
}

private final class RightClickHostingView<Content: View>: NSHostingView<Content> {
    var onRightClick: ((NSRect) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        guard let window else { return }
        let anchorInWindow = convert(bounds, to: nil)
        let anchorOnScreen = window.convertToScreen(anchorInWindow)
        onRightClick?(anchorOnScreen)
    }
}

/// Simple left-to-right flow for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
