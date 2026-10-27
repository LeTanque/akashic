import SwiftUI

/// Todo titles are plain text everywhere — no markdown parsing or preview.
struct TodoTitleText: View {
    @Environment(\.textZoom) private var textZoom

    let title: String
    var pointSize: CGFloat = AkashicFont.body
    var weight: Font.Weight = .regular
    var foreground: Color = CyberpunkTheme.textPrimary
    var completed: Bool = false

    private var displayText: String {
        title.isEmpty ? "Untitled" : title
    }

    var body: some View {
        Text(displayText)
            .font(AkashicFont.mono(pointSize, weight: weight, zoom: textZoom))
            .foregroundStyle(completed ? CyberpunkTheme.completedShaded : foreground)
            .strikethrough(completed, color: CyberpunkTheme.completedShaded)
    }
}

struct PlainTitleField: View {
    @Environment(\.textZoom) private var textZoom

    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        MarkdownSourceEditor(
            text: $text,
            fontSize: AkashicFont.body * textZoom,
            accessibilityLabel: "Title",
            onChange: onCommit
        )
        .frame(minHeight: 56 * textZoom)
        .padding(8)
        .cyberPanel()
    }
}
