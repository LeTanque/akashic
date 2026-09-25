import SwiftUI
import AppKit

struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    GlassBackground()
                    CyberpunkTheme.panel.opacity(0.55)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CyberpunkTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func glassPanel() -> some View {
        modifier(GlassPanel())
    }
}
