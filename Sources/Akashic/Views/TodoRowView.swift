import SwiftUI

struct TodoRowView: View {
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
                        font: compact ? .callout.weight(.semibold) : .body.weight(.semibold),
                        completed: todo.completed
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if !compact, !todo.description.isEmpty {
                    Button(action: onSelect) {
                        MarkdownText(
                            markdown: todo.description,
                            font: .caption,
                            foreground: CyberpunkTheme.textSecondary,
                            completed: todo.completed
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Text(todo.priority.label.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(CyberpunkTheme.priorityColor(todo.priority))
                    Text("·")
                        .foregroundStyle(CyberpunkTheme.textSecondary)
                    Text("Created \(todo.createdOn.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(CyberpunkTheme.textSecondary)
                }
            }
        }
        .padding(.vertical, compact ? 4 : 6)
    }
}
