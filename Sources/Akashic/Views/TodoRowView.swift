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
                            font: compact
                                ? .system(.callout, design: .monospaced).weight(.semibold)
                                : .system(.body, design: .monospaced).weight(.semibold),
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
                                font: .system(.caption, design: .monospaced),
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
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(CyberpunkTheme.priorityColor(todo.priority))
                            Text("·")
                                .foregroundStyle(CyberpunkTheme.completedShaded)
                            Text("Created \(todo.createdOn.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(CyberpunkTheme.completedShaded)
                        }
                    }
                }
            }
        .padding(.vertical, compact ? 6 : 8)
        .padding(.horizontal, compact ? 0 : 4)
    }
}
