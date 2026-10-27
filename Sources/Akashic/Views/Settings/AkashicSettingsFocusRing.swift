import SwiftUI

private struct AkashicSettingsFocusRingModifier: ViewModifier {
    var inset: CGFloat = 2

    @Environment(\.isFocused) private var isFocused

    func body(content: Content) -> some View {
        content
            .focusEffectDisabled()
            .overlay {
                if isFocused {
                    Rectangle()
                        .stroke(AkashicSettingsChrome.accent, lineWidth: 1.5)
                        .shadow(color: AkashicSettingsChrome.accent.opacity(0.55), radius: 4)
                        .padding(-inset)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Themed keyboard focus ring for Settings controls (replaces the system blue ring).
    func akashicSettingsFocusRing(inset: CGFloat = 2) -> some View {
        modifier(AkashicSettingsFocusRingModifier(inset: inset))
    }
}
