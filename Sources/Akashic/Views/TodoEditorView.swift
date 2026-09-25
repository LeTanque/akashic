import SwiftUI

struct TodoEditorView: View {
    @EnvironmentObject private var store: TodoStore
    @State private var draft: TodoItem
    @State private var hasCompleteBy: Bool

    init(todo: TodoItem) {
        _draft = State(initialValue: todo)
        _hasCompleteBy = State(initialValue: todo.completeBy != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    CompletionCheckbox(completed: draft.completed) {
                        store.toggleCompletion(for: draft.id)
                        if let updated = store.todos.first(where: { $0.id == draft.id }) {
                            draft = updated
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title (markdown)")
                            .font(.caption)
                            .foregroundStyle(CyberpunkTheme.textSecondary)
                        TextEditor(text: $draft.title)
                            .font(.body)
                            .frame(minHeight: 60)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .glassPanel()
                            .onChange(of: draft.title) { _, _ in commit() }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description (markdown)")
                        .font(.caption)
                        .foregroundStyle(CyberpunkTheme.textSecondary)
                    TextEditor(text: $draft.description)
                        .font(.callout)
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .glassPanel()
                        .onChange(of: draft.description) { _, _ in commit() }
                }

                previewSection

                metadataSection
            }
            .padding(20)
        }
        .onChange(of: store.selectedTodoID) { _, _ in
            if let todo = store.selectedTodo {
                draft = todo
                hasCompleteBy = todo.completeBy != nil
            }
        }
        .onReceive(store.objectWillChange) { _ in
            if let todo = store.todos.first(where: { $0.id == draft.id }) {
                draft.completed = todo.completed
                draft.completedAt = todo.completedAt
                draft.updatedAt = todo.updatedAt
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CyberpunkTheme.neonCyan)
            MarkdownText(markdown: draft.title.isEmpty ? "Untitled" : draft.title, font: .title3.weight(.semibold), completed: draft.completed)
            if !draft.description.isEmpty {
                MarkdownText(markdown: draft.description, font: .body, foreground: CyberpunkTheme.textSecondary, completed: draft.completed)
            }
        }
        .padding(12)
        .glassPanel()
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Created") {
                Text(draft.createdOn.formatted(date: .complete, time: .shortened))
                    .foregroundStyle(CyberpunkTheme.textSecondary)
            }

            Picker("Priority", selection: $draft.priority) {
                ForEach(TodoPriority.allCases, id: \.self) { p in
                    Text(p.label).tag(p)
                }
            }
            .onChange(of: draft.priority) { _, _ in commit() }

            Toggle("Complete by", isOn: $hasCompleteBy)
                .onChange(of: hasCompleteBy) { _, enabled in
                    if !enabled {
                        draft.completeBy = nil
                        commit()
                    } else if draft.completeBy == nil {
                        draft.completeBy = Date()
                        commit()
                    }
                }

            if hasCompleteBy {
                DatePicker(
                    "Due",
                    selection: Binding(
                        get: { draft.completeBy ?? Date() },
                        set: { draft.completeBy = $0; commit() }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            if let completedAt = draft.completedAt {
                LabeledContent("Completed at") {
                    Text(completedAt.formatted(date: .complete, time: .shortened))
                        .foregroundStyle(CyberpunkTheme.neonGreen)
                }
            }

            HStack {
                Spacer()
                Button("Delete todo", role: .destructive) {
                    store.delete(draft)
                }
            }
        }
        .padding(12)
        .glassPanel()
    }

    private func commit() {
        store.update(draft)
    }
}
