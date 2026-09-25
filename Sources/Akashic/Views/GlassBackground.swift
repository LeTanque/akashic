import SwiftUI

/// Solid cyberpunk surface — replaces prior NSVisualEffectView glass panels.
enum CyberSurface {
    static func fill() -> some View {
        CyberpunkTheme.background
    }
}

/// Kept for call-site stability; no longer uses translucency.
struct GlassBackground: View {
    var body: some View {
        CyberpunkTheme.background
    }
}

struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(CyberPanelModifier())
    }
}

extension View {
    func glassPanel() -> some View {
        cyberPanel()
    }
}
