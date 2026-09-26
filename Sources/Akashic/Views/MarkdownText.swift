import AppKit
import SwiftUI

/// Single markdown stack for list rows and the live description preview.
/// Uses Foundation `AttributedString(markdown:)` with partial parse so incomplete
/// typing (unclosed `**`, half-finished links) still renders instead of falling back
/// to a blank or fully-plain dump.
enum MarkdownRenderer {
    static func attributedString(from markdown: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        do {
            return try AttributedString(markdown: markdown, options: options)
        } catch {
            return AttributedString(markdown)
        }
    }
}

struct MarkdownText: View {
    @Environment(\.textZoom) private var textZoom

    let markdown: String
    var pointSize: CGFloat = AkashicFont.body
    var weight: Font.Weight = .regular
    var foreground: Color = CyberpunkTheme.textPrimary
    var completed: Bool = false

    var body: some View {
        Text(MarkdownRenderer.attributedString(from: markdown))
            .font(AkashicFont.mono(pointSize, weight: weight, zoom: textZoom))
            .foregroundStyle(completed ? CyberpunkTheme.completedShaded : foreground)
            .strikethrough(completed, color: CyberpunkTheme.completedShaded)
            .environment(\.openURL, OpenURLAction { url in
                NSWorkspace.shared.open(url)
                return .handled
            })
    }
}
