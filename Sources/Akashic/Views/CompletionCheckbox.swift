import SwiftUI

struct CompletionCheckbox: View {
    let completed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(completed ? CyberpunkTheme.neonGreen : CyberpunkTheme.neonCyan, lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .shadow(color: (completed ? CyberpunkTheme.neonGreen : CyberpunkTheme.neonCyan).opacity(0.45), radius: 4)

                if completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CyberpunkTheme.neonGreen)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(completed ? "Mark incomplete" : "Mark complete")
        .help(completed ? "Mark incomplete" : "Mark complete")
    }
}
