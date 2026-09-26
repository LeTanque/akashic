import SwiftUI

struct TodoEditorView: View {
    @EnvironmentObject private var store: TodoStore
    @Environment(\.textZoom) private var textZoom
    @State private var draft: TodoItem
    @State private var hasCompleteBy: Bool

    init(todo: TodoItem) {
        _draft = State(initialValue: todo)
        _hasCompleteBy = State(initialValue: todo.completeBy != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title (markdown)")
                        .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.completedShaded)
                    HStack(alignment: .top, spacing: 8) {
                        TextEditor(text: $draft.title)
                            .font(AkashicFont.mono(AkashicFont.body, zoom: textZoom))
                            .foregroundStyle(CyberpunkTheme.neonCyan)
                            .frame(minHeight: 60 * textZoom)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .cyberPanel()
                            .onChange(of: draft.title) { _, _ in commitIfChanged() }

                        CompletionCheckbox(
                            completed: draft.completed,
                            style: .editorBlock
                        ) {
                            store.toggleCompletion(for: draft.id)
                            if let updated = store.todos.first(where: { $0.id == draft.id }) {
                                draft = updated
                            }
                        }
                        .frame(minHeight: 60 * textZoom)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description (markdown)")
                        .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.completedShaded)
                    MarkdownDescriptionEditor(
                        text: $draft.description,
                        onCommit: commitIfChanged
                    )
                }

                metadataSection
            }
            .padding(20)
        }
        .background(Color.clear)
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

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Created") {
                Text(draft.createdOn.formatted(date: .complete, time: .shortened))
                    .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                    .foregroundStyle(CyberpunkTheme.completedShaded)
            }

            LabeledContent("Priority") {
                Picker("", selection: $draft.priority) {
                    ForEach(TodoPriority.allCases, id: \.self) { p in
                        Text(p.label)
                            .foregroundStyle(CyberpunkTheme.priorityColor(p))
                            .tag(p)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .foregroundStyle(CyberpunkTheme.priorityColor(draft.priority))
            .onChange(of: draft.priority) { _, _ in commitIfChanged() }

            Toggle("Complete by", isOn: $hasCompleteBy)
                .onChange(of: hasCompleteBy) { _, enabled in
                    if !enabled {
                        draft.completeBy = nil
                        commitIfChanged()
                    } else if draft.completeBy == nil {
                        draft.completeBy = Date()
                        commitIfChanged()
                    }
                }

            if hasCompleteBy {
                DatePicker(
                    "Due",
                    selection: Binding(
                        get: { draft.completeBy ?? Date() },
                        set: { draft.completeBy = $0; commitIfChanged() }
                    ),
                    displayedComponents: [.date, .hourAndMinute]
                )
            }

            if let completedAt = draft.completedAt {
                LabeledContent("Completed at") {
                    Text(completedAt.formatted(date: .complete, time: .shortened))
                        .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.completedShaded)
                }
            }

            HStack {
                Spacer()
                Button("Delete todo", role: .destructive) {
                    store.delete(draft)
                }
                .buttonStyle(CyberDestructiveBorderedButtonStyle())
                .help("Delete this todo permanently")
            }
        }
        .padding(12)
        .cyberPanel()
    }

    /// Skip no-op writes so selecting a todo (which reloads `draft`) cannot bump `updated_at`.
    private func commitIfChanged() {
        guard let existing = store.todos.first(where: { $0.id == draft.id }) else { return }
        guard !draft.hasSameEditableContent(as: existing) else { return }
        var toSave = existing
        toSave.title = draft.title
        toSave.description = draft.description
        toSave.priority = draft.priority
        toSave.completeBy = draft.completeBy
        store.update(toSave)
    }
}
