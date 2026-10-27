import SwiftUI

struct ThemedCheckboxToggleStyle: ToggleStyle {
    var accent: Color = CyberpunkTheme.neonCyan
    var labelFont: Font = AkashicSettingsChrome.font(11, bold: true)
    var subtitleFont: Font = AkashicSettingsChrome.font(9)

    func makeBody(configuration: Configuration) -> some View {
        ThemedCheckboxRow(
            isOn: configuration.isOn,
            accent: accent,
            labelFont: labelFont,
            subtitleFont: subtitleFont,
            label: { configuration.label },
            toggle: { configuration.isOn.toggle() }
        )
    }
}

struct ThemedCheckboxRow<Label: View>: View {
    let isOn: Bool
    var accent: Color = CyberpunkTheme.neonCyan
    var labelFont: Font = AkashicSettingsChrome.font(11, bold: true)
    var subtitleFont: Font = AkashicSettingsChrome.font(9)
    @ViewBuilder var label: () -> Label
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 10) {
                checkboxGlyph
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityAddTraits(.isButton)
    }

    private var checkboxGlyph: some View {
        ZStack {
            Rectangle()
                .fill(fillColor)
                .overlay(
                    Rectangle()
                        .stroke(borderColor, lineWidth: isHovered ? 1.5 : 1)
                )
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black)
            }
        }
        .frame(width: 18, height: 18)
        .shadow(color: accent.opacity(isHovered ? 0.45 : 0.25), radius: isHovered ? 5 : 3)
    }

    private var fillColor: Color {
        if isOn {
            return accent
        }
        if isHovered {
            return CyberpunkTheme.completedShaded.opacity(0.35)
        }
        return CyberpunkTheme.background
    }

    private var borderColor: Color {
        accent.opacity(isOn || isHovered ? 1 : 0.85)
    }
}

extension View {
    func themedCheckboxToggleStyle(
        accent: Color = CyberpunkTheme.neonCyan
    ) -> some View {
        toggleStyle(ThemedCheckboxToggleStyle(accent: accent))
    }
}
