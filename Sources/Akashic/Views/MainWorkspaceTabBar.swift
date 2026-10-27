import SwiftUI

struct MainWorkspaceTabBar: View {
    @Environment(\.textZoom) private var textZoom
    @Binding var selection: MainAppTab
    var onSelect: (MainAppTab) -> Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainAppTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.28))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(CyberpunkTheme.neonCyan.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func tabButton(_ tab: MainAppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            guard tab != selection else { return }
            guard onSelect(tab) else { return }
            selection = tab
        } label: {
            Text(tab.label.uppercased())
                .font(AkashicFont.mono(AkashicFont.callout, weight: isSelected ? .bold : .regular, zoom: textZoom))
                .foregroundStyle(isSelected ? CyberpunkTheme.neonCyan : CyberpunkTheme.readableMutedCyan)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Rectangle()
                        .fill(isSelected ? CyberpunkTheme.neonCyan.opacity(0.12) : Color.clear)
                )
                .overlay(
                    Rectangle()
                        .stroke(
                            isSelected ? CyberpunkTheme.neonCyan.opacity(0.85) : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
