import AppKit
import SwiftUI

// MARK: - Geometry (unit-testable)

enum AkashicScrollerGeometry {
    static let knobWidth: CGFloat = 14
    static let gripLineCount = 3
    static let gripLineHeight: CGFloat = 1
    static let gripLineSpacing: CGFloat = 3
    static let gripInset: CGFloat = 3

    static func knobRect(in bounds: NSRect, knobProportion: CGFloat, knobProportionMin: CGFloat) -> NSRect {
        let proportion = max(knobProportion, knobProportionMin)
        let length = bounds.height * proportion
        let travel = max(bounds.height - length, 0)
        let y = bounds.maxY - length - travel * 0.5
        return NSRect(x: bounds.minX, y: y, width: bounds.width, height: length)
    }

    static func gripLineRects(in knob: NSRect) -> [NSRect] {
        let totalHeight = CGFloat(gripLineCount) * gripLineHeight + CGFloat(gripLineCount - 1) * gripLineSpacing
        var y = knob.midY + totalHeight / 2 - gripLineHeight
        var rects: [NSRect] = []
        for _ in 0..<gripLineCount {
            let rect = NSRect(
                x: knob.minX + gripInset,
                y: y,
                width: knob.width - gripInset * 2,
                height: gripLineHeight
            )
            rects.append(rect)
            y -= gripLineHeight + gripLineSpacing
        }
        return rects
    }
}

// MARK: - Custom scroller

final class AkashicScroller: NSScroller {
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        AkashicScrollerGeometry.knobWidth
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // Dark track matching the app chrome, with a faint cyan rail on the inner edge.
        NSColor(white: 0, alpha: 0.35).setFill()
        slotRect.fill()
        NSColor(srgbRed: 0, green: 217 / 255, blue: 1, alpha: 0.25).setFill()
        NSRect(x: slotRect.minX, y: slotRect.minY, width: 1, height: slotRect.height).fill()
    }

    override func drawKnob() {
        let slot = rect(for: .knobSlot)
        let knob = rect(for: .knob)
        guard knob.height > 4 else { return }

        NSColor(white: 0, alpha: 0.35).setFill()
        knob.fill()

        let outline = NSColor(srgbRed: 0, green: 217 / 255, blue: 1, alpha: 0.95)
        outline.setStroke()
        let path = NSBezierPath(rect: knob.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        path.stroke()

        outline.setFill()
        for line in AkashicScrollerGeometry.gripLineRects(in: knob) {
            line.fill()
        }

        _ = slot
    }
}

// MARK: - Installer

enum AkashicScrollViewPatcher {
    static func patch(_ scrollView: NSScrollView) {
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = true // no empty track on fields whose content fits
        scrollView.hasVerticalScroller = true
        if let vertical = scrollView.verticalScroller, !(vertical is AkashicScroller) {
            let themed = AkashicScroller(frame: vertical.frame)
            themed.scrollerStyle = .legacy
            scrollView.verticalScroller = themed
        }
        if scrollView.hasHorizontalScroller, let horizontal = scrollView.horizontalScroller, !(horizontal is AkashicScroller) {
            let themed = AkashicScroller(frame: horizontal.frame)
            themed.scrollerStyle = .legacy
            scrollView.horizontalScroller = themed
        }
    }

    /// Themes every scroll view under `root` that already shows a vertical scroller
    /// (SwiftUI `List` / `ScrollView` backing views are siblings of the installer, not ancestors).
    static func patchHierarchy(root: NSView) {
        if let scrollView = root as? NSScrollView, scrollView.hasVerticalScroller {
            patch(scrollView)
        }
        for subview in root.subviews {
            patchHierarchy(root: subview)
        }
    }
}

private final class AkashicScrollerInstallerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        schedulePatch()
    }

    func schedulePatch() {
        // SwiftUI builds its NSScrollView lazily; patch now and once more after layout settles.
        for delay in [0.0, 0.3] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.patch()
            }
        }
    }

    private func patch() {
        if let scrollView = enclosingScrollView {
            AkashicScrollViewPatcher.patch(scrollView)
        }
        if let root = window?.contentView {
            AkashicScrollViewPatcher.patchHierarchy(root: root)
        }
    }
}

private struct AkashicScrollerInstaller: NSViewRepresentable {
    func makeNSView(context: Context) -> AkashicScrollerInstallerView {
        AkashicScrollerInstallerView(frame: .zero)
    }

    func updateNSView(_ nsView: AkashicScrollerInstallerView, context: Context) {
        nsView.schedulePatch()
    }
}

extension View {
    func akashicScrollers() -> some View {
        background(AkashicScrollerInstaller())
    }
}
