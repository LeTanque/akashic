import SwiftUI

struct TodoRowView: View {
    @Environment(\.textZoom) private var textZoom

    let todo: TodoItem
    var compact: Bool = false
    let onToggleComplete: () -> Void
    let onSelect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CompletionCheckbox(completed: todo.completed, action: onToggleComplete)

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Button(action: onSelect) {
                    MarkdownText(
                        markdown: todo.title.isEmpty ? "Untitled" : todo.title,
                        pointSize: compact ? AkashicFont.callout : AkashicFont.body,
                        weight: .semibold,
                        foreground: CyberpunkTheme.neonCyan,
                        completed: todo.completed
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if !compact, !todo.description.isEmpty {
                    Button(action: onSelect) {
                        MarkdownText(
                            markdown: todo.description,
                            pointSize: AkashicFont.caption,
                            foreground: CyberpunkTheme.completedShaded.opacity(0.9),
                            completed: todo.completed
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                if !compact {
                    HStack(spacing: 8) {
                        Text(todo.priority.label.uppercased())
                            .font(AkashicFont.mono(AkashicFont.micro, weight: .bold, zoom: textZoom))
                            .foregroundStyle(CyberpunkTheme.priorityColor(todo.priority))
                        Text("·")
                            .font(AkashicFont.mono(AkashicFont.caption2, zoom: textZoom))
                            .foregroundStyle(CyberpunkTheme.completedShaded)
                        Text("Created \(todo.createdOn.formatted(date: .abbreviated, time: .shortened))")
                            .font(AkashicFont.mono(AkashicFont.caption2, zoom: textZoom))
                            .foregroundStyle(CyberpunkTheme.completedShaded)
                    }
                }
            }
        }
        .padding(.vertical, compact ? 6 : 8)
        .padding(.horizontal, compact ? 0 : 4)
    }
}
