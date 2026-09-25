import SwiftUI

struct CompletionCheckbox: View {
    let completed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(completed ? CyberpunkTheme.neonCyan : CyberpunkTheme.background)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Rectangle()
                            .stroke(CyberpunkTheme.neonCyan, lineWidth: 1)
                    )
                    .shadow(color: CyberpunkTheme.neonCyan.opacity(completed ? 0.35 : 0.45), radius: 4)

                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(completed ? "Mark incomplete" : "Mark complete")
        .help(completed ? "Mark incomplete" : "Mark complete")
    }
}
