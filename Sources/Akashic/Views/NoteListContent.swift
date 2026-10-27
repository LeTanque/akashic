import SwiftUI

struct NoteListContent: View {
    @EnvironmentObject private var noteStore: NoteStore
    @Environment(\.textZoom) private var textZoom

    let notes: [NoteItem]
    let onSelect: (NoteItem) -> Void
    var onRecolorTag: (AkashicTag, AkashicTagColor) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(notes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.title.isEmpty ? "Untitled" : note.title)
                            .font(AkashicFont.mono(AkashicFont.body, weight: .semibold, zoom: textZoom))
                            .foregroundStyle(CyberpunkTheme.textPrimary)
                            .lineLimit(2)
                        if !note.tags.isEmpty {
                            NoteTagChipRow(tags: note.tags, onRecolor: onRecolorTag)
                        }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(note) }
                    .id(note.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(rowBackground(for: note))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(CyberpunkTheme.rowDivider)
                            .frame(height: 1)
                    }
                }
            }
            .listStyle(.plain)
            .akashicScrollers()
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 1)
            .onChange(of: noteStore.revealNoteInListID) { _, id in
                guard let id, notes.contains(where: { $0.id == id }) else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.22)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }

    private func rowBackground(for note: NoteItem) -> Color {
        noteStore.selectedNoteID == note.id
            ? CyberpunkTheme.completedShaded.opacity(0.28)
            : Color.clear
    }
}
