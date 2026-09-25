import AppKit
import SwiftUI

struct MarkdownText: View {
    let markdown: String
    var font: Font = .body
    var foreground: Color = CyberpunkTheme.textPrimary
    var completed: Bool = false

    var body: some View {
        Group {
            if let attributed = try? AttributedString(markdown: markdown) {
                Text(attributed)
            } else {
                Text(markdown)
            }
        }
        .font(font)
        .foregroundStyle(completed ? CyberpunkTheme.textSecondary : foreground)
        .strikethrough(completed, color: CyberpunkTheme.textSecondary)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            NSWorkspace.shared.open(url)
            return .handled
        })
    }
}
