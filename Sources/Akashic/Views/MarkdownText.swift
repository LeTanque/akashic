import AkashicCore
import AppKit
import SwiftUI

struct MarkdownText: View {
    @Environment(\.textZoom) private var textZoom

    let markdown: String
    var pointSize: CGFloat = AkashicFont.body
    var weight: Font.Weight = .regular
    var foreground: Color = CyberpunkTheme.textPrimary
    var completed: Bool = false

    var body: some View {
        Text(
            MarkdownRenderer.attributedString(
                from: markdown,
                basePointSize: pointSize * textZoom
            )
        )
        .font(AkashicFont.mono(pointSize, weight: weight, zoom: textZoom))
        .foregroundStyle(completed ? CyberpunkTheme.completedShaded : foreground)
        .strikethrough(completed, color: CyberpunkTheme.completedShaded)
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }
}
