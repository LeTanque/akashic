import SwiftUI

struct TodoEditorView: View {
    @EnvironmentObject private var store: TodoStore
    @ObservedObject var session: TodoEditorSession
    @Environment(\.textZoom) private var textZoom
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Title")
                        .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.completedShaded)
                    HStack(alignment: .top, spacing: 8) {
                        PlainTitleField(text: titleBinding, onCommit: {})

                        CompletionCheckbox(
                            completed: session.form.draft.completed,
                            style: .editorBlock
                        ) {
                            if session.form.isNew {
                                session.toggleDraftCompletion()
                            } else {
                                session.applyCompletionToggle(for: session.form.draft.id, store: store)
                            }
                        }
                        .frame(minHeight: 60 * textZoom)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Description (markdown)")
                        .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.completedShaded)
                    MarkdownLiveEditor(
                        text: descriptionBinding,
                        onCommit: {},
                        sourceAccessibilityLabel: "Description markdown source"
                    )
                }

                metadataSection
                saveActionRow
            }
            .padding(20)
        }
        .akashicScrollers()
        .background(Color.clear)
        .onReceive(store.objectWillChange) { _ in
            guard !session.form.isNew,
                  let updated = store.todos.first(where: { $0.id == session.form.draft.id })
            else { return }
            session.syncCompletionFromStore(updated)
        }
        .onChange(of: session.requestTitleFocus) { _, token in
            guard token != nil else { return }
            titleFieldFocused = true
        }
        .focused($titleFieldFocused)
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { session.form.draft.title },
            set: { newValue in session.mutateForm { $0.draft.title = newValue } }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { session.form.draft.description },
            set: { newValue in session.mutateForm { $0.draft.description = newValue } }
        )
    }

    private var priorityBinding: Binding<TodoPriority> {
        Binding(
            get: { session.form.draft.priority },
            set: { newValue in session.mutateForm { $0.draft.priority = newValue } }
        )
    }

    private var hasCompleteByBinding: Binding<Bool> {
        Binding(
            get: { session.form.hasCompleteBy },
            set: { enabled in
                session.mutateForm { form in
                    form.hasCompleteBy = enabled
                    if !enabled {
                        form.draft.completeBy = nil
                    }
                }
            }
        )
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.form.isNew {
                LabeledContent("Created") {
                    Text(session.form.draft.createdOn.formatted(date: .complete, time: .shortened))
                        .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.readableMutedCyan)
                }
            }

            LabeledContent("Priority") {
                ThemedDropdown(
                    accessibilityTitle: "Priority",
                    selection: priorityBinding,
                    options: Array(TodoPriority.allCases),
                    label: { $0.label },
                    accent: { CyberpunkTheme.priorityColor($0) }
                )
            }
            .foregroundStyle(CyberpunkTheme.priorityColor(session.form.draft.priority))

            Toggle(isOn: hasCompleteByBinding) {
                Text("Complete by")
                    .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                    .foregroundStyle(CyberpunkTheme.neonCyan)
            }
            .themedCheckboxToggleStyle(checkboxSize: ThemedCheckboxMetrics.completeByEditor)
            .accessibilityLabel("Complete by")

            if session.form.hasCompleteBy {
                ThemedDueDatePicker(savedCompleteBy: session.form.draft.completeBy) { saved in
                    session.mutateForm { $0.draft.completeBy = saved }
                }
            }

            if let completedAt = session.form.draft.completedAt {
                LabeledContent("Completed at") {
                    Text(completedAt.formatted(date: .complete, time: .shortened))
                        .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.completedShaded)
                }
            }

            if !session.form.isNew {
                HStack {
                    Spacer()
                    Button("Delete todo", role: .destructive) {
                        let item = session.form.draft
                        store.delete(item)
                        session.mutateForm { $0.reset() }
                    }
                    .buttonStyle(CyberDestructiveBorderedButtonStyle())
                    .help("Delete this todo permanently")
                }
            }
        }
        .padding(12)
        .cyberPanel()
    }

    private var saveActionRow: some View {
        HStack(spacing: 8) {
            if session.form.canDiscard {
                Button("Revert") {
                    session.mutateForm { $0.discard() }
                }
                .buttonStyle(CyberBorderedButtonStyle())
                .help("Discard unsaved edits")
            }

            Spacer()

            Button {
                session.save(store: store)
            } label: {
                Text("SAVE")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(CyberBorderedButtonStyle())
            .disabled(!session.form.canSave)
            .keyboardShortcut("s", modifiers: .command)
            .help("Save todo")
        }
        .padding(.top, 4)
    }
}
