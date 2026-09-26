import AppKit
import SwiftUI

/// AppKit vibrancy layer. `behindWindow` samples the desktop; do not wrap
/// ancestors in `compositingGroup()`, `opacity`, or a full-view `shadow`.
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.wantsLayer = true
        view.autoresizingMask = [.width, .height]
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = cornerRadius > 0
    }
}

/// Dark smoked glass: desktop vibrancy with a light black veil so neon still reads.
struct SmokedGlassFill: View {
    var material: NSVisualEffectView.Material = .hudWindow
    var smokeOpacity: Double = 0.38
    /// Extra darkness in the leftover titlebar / top chrome band only.
    var topChromeVeilOpacity: Double = 0
    var topChromeVeilHeight: CGFloat = 0

    var body: some View {
        ZStack {
            GlassBackground(material: material, blendingMode: .behindWindow)
            Color.black.opacity(smokeOpacity)
            if topChromeVeilHeight > 0, topChromeVeilOpacity > 0 {
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(topChromeVeilOpacity), location: 0),
                            .init(color: Color.black.opacity(topChromeVeilOpacity * 0.55), location: 0.5),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: topChromeVeilHeight)
                    .allowsHitTesting(false)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

enum CyberSurface {
    static func fill() -> some View {
        SmokedGlassFill()
    }
}

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    GlassBackground(
                        material: .hudWindow,
                        blendingMode: .behindWindow,
                        cornerRadius: cornerRadius
                    )
                    CyberpunkTheme.panel.opacity(0.55)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(CyberpunkTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 0) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}
