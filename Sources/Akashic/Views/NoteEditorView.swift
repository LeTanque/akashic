import SwiftUI

struct NoteEditorView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @ObservedObject var session: NoteEditorSession
    @Environment(\.textZoom) private var textZoom
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleSection
                tagsSection
                bodySection
                metadataSection
                saveActionRow
            }
            .padding(20)
        }
        .akashicScrollers()
        .background(Color.clear)
        .onChange(of: session.requestTitleFocus) { _, token in
            guard token != nil else { return }
            titleFieldFocused = true
        }
        .onReceive(noteStore.objectWillChange) { _ in
            guard !session.form.isNew,
                  let updated = noteStore.notes.first(where: { $0.id == session.form.draft.id })
            else { return }
            session.mutateForm { $0.refreshTagColors(from: updated) }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Title")
                .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.completedShaded)
            PlainTitleField(text: titleBinding, onCommit: {})
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.completedShaded)
            NoteTagChipRow(
                tags: session.form.draft.tags,
                onRemove: { tag in session.mutateForm { $0.removeTag(tag) } },
                onRecolor: recolorTag
            )
            TagInputField(text: tagInputBinding, onCommit: {
                session.mutateForm { $0.commitTagsFromInput() }
            })
        }
    }

    private var bodySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Body (markdown)")
                .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.completedShaded)
            NoteBodySplitEditor(text: bodyBinding)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !session.form.isNew {
                LabeledContent("Created") {
                    Text(session.form.draft.createdAt.formatted(date: .complete, time: .shortened))
                        .font(AkashicFont.mono(AkashicFont.callout, zoom: textZoom))
                        .foregroundStyle(CyberpunkTheme.readableMutedCyan)
                }
            }

            if !session.form.isNew {
                HStack {
                    Spacer()
                    Button("Delete note", role: .destructive) {
                        let item = session.form.draft
                        noteStore.delete(item)
                        session.mutateForm { $0.reset() }
                    }
                    .buttonStyle(CyberDestructiveBorderedButtonStyle())
                    .help("Delete this note permanently")
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
            }
            Spacer()
            Button {
                session.save(store: noteStore)
            } label: {
                Text("SAVE")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(CyberBorderedButtonStyle())
            .disabled(!session.form.canSave)
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.top, 4)
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { session.form.draft.title },
            set: { newValue in session.mutateForm { $0.draft.title = newValue } }
        )
    }

    private var bodyBinding: Binding<String> {
        Binding(
            get: { session.form.draft.body },
            set: { newValue in session.mutateForm { $0.draft.body = newValue } }
        )
    }

    private var tagInputBinding: Binding<String> {
        Binding(
            get: { session.form.tagInput },
            set: { newValue in session.mutateForm { $0.tagInput = newValue } }
        )
    }

    private func recolorTag(_ tag: AkashicTag, color: AkashicTagColor) {
        _ = noteStore.setTagColor(name: tag.name, color: color)
        if session.form.draft.tags.contains(where: { $0.nameKey == tag.nameKey }) {
            session.mutateForm { form in
                for index in form.draft.tags.indices where form.draft.tags[index].nameKey == tag.nameKey {
                    form.draft.tags[index].color = color
                }
            }
        }
    }
}

private struct TagInputField: View {
    @Environment(\.textZoom) private var textZoom
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        MarkdownSourceEditor(
            text: $text,
            fontSize: AkashicFont.callout * textZoom,
            accessibilityLabel: "Tag input",
            onChange: {
                if text.contains("\n") {
                    onCommit()
                }
            }
        )
        .frame(minHeight: 36 * textZoom, maxHeight: 48 * textZoom)
        .padding(6)
        .cyberPanel()
        .onSubmit(onCommit)
    }
}

struct NoteBodySplitEditor: View {
    @Environment(\.textZoom) private var textZoom
    @Binding var text: String

    var body: some View {
        GeometryReader { geo in
            let half = max(80, geo.size.height / 2)
            VStack(spacing: 0) {
                MarkdownSourceEditor(
                    text: $text,
                    fontSize: AkashicFont.callout * textZoom,
                    accessibilityLabel: "Note body markdown source",
                    onChange: {}
                )
                .frame(height: half)
                .padding(8)

                Rectangle()
                    .fill(CyberpunkTheme.neonCyan.opacity(0.35))
                    .frame(height: 1)

                Group {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Formatted markdown preview")
                            .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                            .foregroundStyle(CyberpunkTheme.completedShaded)
                            .italic()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        ScrollView {
                            MarkdownText(
                                markdown: text,
                                pointSize: AkashicFont.callout,
                                foreground: CyberpunkTheme.neonCyan
                            )
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .akashicScrollers()
                    }
                }
                .frame(height: half)
                .padding(8)
            }
            .cyberPanel()
        }
        .frame(minHeight: 280 * textZoom)
    }
}
