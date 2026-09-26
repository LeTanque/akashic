import AppKit
import SwiftUI

/// Description field: editable markdown source plus a live formatted preview.
///
/// The `TextEditor`-class surface is an `NSTextView` so smart quotes/dashes stay
/// off (they break CommonMark) and the caret/selection stay on the source string.
/// Formatted output is the same `MarkdownRenderer` / `MarkdownText` stack used
/// by list rows — no preview toggle, updates on every keystroke.
struct MarkdownDescriptionEditor: View {
    @Environment(\.textZoom) private var textZoom

    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarkdownSourceEditor(
                text: $text,
                fontSize: AkashicFont.callout * textZoom,
                onChange: onCommit
            )
            .frame(minHeight: 100 * textZoom)
            .padding(8)

            Rectangle()
                .fill(CyberpunkTheme.neonCyan.opacity(0.35))
                .frame(height: 1)

            livePreview
                .frame(maxWidth: .infinity, minHeight: 72 * textZoom, alignment: .topLeading)
                .padding(8)
        }
        .cyberPanel()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var livePreview: some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Formatted markdown appears here as you type")
                .font(AkashicFont.mono(AkashicFont.caption, zoom: textZoom))
                .foregroundStyle(CyberpunkTheme.completedShaded)
                .italic()
                .accessibilityLabel("Empty live markdown preview")
        } else {
            MarkdownText(
                markdown: text,
                pointSize: AkashicFont.callout,
                foreground: CyberpunkTheme.neonCyan
            )
            .textSelection(.enabled)
            .accessibilityLabel("Live markdown preview")
        }
    }
}

/// Plain-string markdown source. Attributes are never written back; the binding
/// is always the raw markdown that SQLite stores.
struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.focusRingType = .none

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.string = text
        textView.setAccessibilityLabel("Description markdown source")
        configureChrome(textView)
        applyTypography(to: textView, force: true)
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        configureChrome(textView)
        applyTypography(to: textView, force: false)

        guard textView.string != text else { return }
        let selected = textView.selectedRange()
        textView.string = text
        let maxLen = (text as NSString).length
        let location = min(selected.location, maxLen)
        let length = min(selected.length, max(0, maxLen - location))
        textView.setSelectedRange(NSRange(location: location, length: length))
    }

    private func configureChrome(_ textView: NSTextView) {
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsImageEditing = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: textView.bounds.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.focusRingType = .none
        textView.insertionPointColor = MarkdownEditorChrome.neonCyan
        textView.selectedTextAttributes = [
            .backgroundColor: MarkdownEditorChrome.selection,
            .foregroundColor: MarkdownEditorChrome.neonCyan,
        ]
    }

    private func applyTypography(to textView: NSTextView, force: Bool) {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let sizeChanged = abs((textView.font?.pointSize ?? 0) - font.pointSize) > 0.05
        guard force || sizeChanged else { return }
        textView.font = font
        textView.textColor = MarkdownEditorChrome.neonCyan
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: MarkdownEditorChrome.neonCyan,
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSourceEditor
        weak var textView: NSTextView?

        init(_ parent: MarkdownSourceEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let next = textView.string
            guard parent.text != next else { return }
            parent.text = next
            parent.onChange()
        }
    }
}

private enum MarkdownEditorChrome {
    static let neonCyan = NSColor(srgbRed: 0, green: 217 / 255, blue: 1, alpha: 1)
    static let selection = NSColor(srgbRed: 0, green: 217 / 255, blue: 1, alpha: 0.28)
}
