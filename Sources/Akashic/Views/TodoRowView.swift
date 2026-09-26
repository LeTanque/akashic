import SwiftUI

struct TodoRowView: View {
    @Environment(\.textZoom) private var textZoom

    let todo: TodoItem
    var compact: Bool = false
    let onToggleComplete: () -> Void
    let onSelect: () -> Void

    private var checkboxGutter: CGFloat { 22 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 10) {
                Color.clear
                    .frame(width: checkboxGutter, height: checkboxGutter)
                rowText
            }
            .padding(.vertical, compact ? 6 : 8)
            .padding(.horizontal, compact ? 0 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            CompletionCheckbox(completed: todo.completed, action: onToggleComplete)
                .padding(.top, compact ? 6 : 8)
                .padding(.leading, compact ? 0 : 4)
        }
    }

    private var rowText: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            MarkdownText(
                markdown: todo.title.isEmpty ? "Untitled" : todo.title,
                pointSize: compact ? AkashicFont.callout : AkashicFont.body,
                weight: .semibold,
                foreground: CyberpunkTheme.neonCyan,
                completed: todo.completed
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if !compact, !todo.description.isEmpty {
                MarkdownText(
                    markdown: todo.description,
                    pointSize: AkashicFont.caption,
                    foreground: CyberpunkTheme.completedShaded.opacity(0.9),
                    completed: todo.completed
                )
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
