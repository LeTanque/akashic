import SwiftUI

enum CompletionCheckboxStyle {
    /// List / popover rows — small square with checkmark when complete.
    case list
    /// Editor title row — tall block fill when complete, no glyph.
    case editorBlock
}

struct CompletionCheckbox: View {
    let completed: Bool
    var style: CompletionCheckboxStyle = .list
    let action: () -> Void

    @State private var isHovered = false

    private var boxWidth: CGFloat {
        style == .editorBlock ? 28 : 22
    }

    private var boxHeight: CGFloat? {
        style == .list ? 22 : nil
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle()
                    .fill(fillColor)
                    .overlay(
                        Rectangle()
                            .stroke(borderColor, lineWidth: isHovered && !completed ? 1.5 : 1)
                    )
                    .shadow(color: shadowColor, radius: isHovered ? 6 : 4)

                if completed, style == .list {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black)
                }
            }
            .frame(width: boxWidth, height: boxHeight)
            .frame(maxHeight: style == .editorBlock ? .infinity : nil)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(completed ? "Mark incomplete" : "Mark complete")
        .help(completed ? "Mark incomplete" : "Mark complete")
    }

    private var fillColor: Color {
        if completed {
            return CyberpunkTheme.neonCyan
        }
        if isHovered {
            return CyberpunkTheme.completedShaded.opacity(0.35)
        }
        return CyberpunkTheme.background
    }

    private var borderColor: Color {
        if isHovered {
            return CyberpunkTheme.neonCyan
        }
        return CyberpunkTheme.neonCyan.opacity(completed ? 1 : 0.85)
    }

    private var shadowColor: Color {
        let base = CyberpunkTheme.neonCyan.opacity(completed ? 0.35 : 0.45)
        if isHovered {
            return CyberpunkTheme.neonCyan.opacity(0.55)
        }
        return base
    }
}
