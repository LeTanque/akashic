import AppKit
import SwiftUI

/// Single markdown stack for list rows and the live title/description previews.
///
/// Foundation `AttributedString(markdown:)` with `.full` syntax attaches
/// `presentationIntent` for lists and headings, but SwiftUI `Text` does not
/// paint those intents (no bullets, no heading size). This renderer keeps the
/// parser, then materializes intents into glyphs and fonts the UI can show.
/// Incomplete typing still uses the partial-failure policy instead of a blank dump.
enum MarkdownRenderer {
    /// Visible unordered-list marker. SwiftUI `Text` will not invent this from
    /// `presentationIntent` alone.
    static let unorderedListBullet: Character = "•"

    static func attributedString(
        from markdown: String,
        basePointSize: CGFloat = AkashicFont.body
    ) -> AttributedString {
        let source = normalizeSmartTypography(markdown)
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        let parsed: AttributedString
        do {
            parsed = try AttributedString(markdown: source, options: options)
        } catch {
            return AttributedString(source)
        }
        var visible = materializeBlockPresentation(parsed, basePointSize: basePointSize)
        emphasizeInlineCode(&visible)
        return visible
    }

    /// macOS smart dash turns a typed `- ` into `– ` / `— `, which is not a
    /// CommonMark list marker. Repair those only at line start so already-saved
    /// titles still parse as lists. Mid-line dashes are left alone.
    static func normalizeSmartTypography(_ markdown: String) -> String {
        let smartDashes: Set<Character> = ["\u{2013}", "\u{2014}", "\u{2212}"]
        var result = ""
        result.reserveCapacity(markdown.count)
        var atLineStart = true
        var index = markdown.startIndex
        while index < markdown.endIndex {
            let character = markdown[index]
            if atLineStart {
                if character == " " || character == "\t" {
                    result.append(character)
                    index = markdown.index(after: index)
                    continue
                }
                if smartDashes.contains(character) {
                    let next = markdown.index(after: index)
                    if next < markdown.endIndex {
                        let following = markdown[next]
                        if following == " " || following == "\t" {
                            result.append("-")
                            index = next
                            atLineStart = false
                            continue
                        }
                    }
                }
                atLineStart = false
            }
            result.append(character)
            if character == "\n" || character == "\r" {
                atLineStart = true
            }
            index = markdown.index(after: index)
        }
        return result
    }

    /// Turn list/heading presentation intents into characters and fonts that
    /// `Text(AttributedString)` actually draws.
    private static func materializeBlockPresentation(
        _ source: AttributedString,
        basePointSize: CGFloat
    ) -> AttributedString {
        var output = AttributedString()
        var emittedMarkerForItem: Int?

        for run in source.runs {
            var fragment = AttributedString(source[run.range])
            let intent = run.presentationIntent

            if let headerLevel = headerLevel(of: intent) {
                applyHeadingStyle(&fragment, level: headerLevel, basePointSize: basePointSize)
            }

            if let list = listContext(of: intent) {
                let fragmentIsBreak = isOnlyNewlines(fragment)
                if emittedMarkerForItem != list.itemID, !fragmentIsBreak {
                    if !output.characters.isEmpty, !endsWithNewline(output) {
                        output += AttributedString("\n")
                    }
                    output += AttributedString(list.marker)
                    emittedMarkerForItem = list.itemID
                }
            } else {
                emittedMarkerForItem = nil
            }

            output += fragment
        }

        return output
    }

    private static func applyHeadingStyle(
        _ fragment: inout AttributedString,
        level: Int,
        basePointSize: CGFloat
    ) {
        let scale: CGFloat
        let weight: Font.Weight
        switch level {
        case 1:
            scale = 1.45
            weight = .bold
        case 2:
            scale = 1.28
            weight = .bold
        case 3:
            scale = 1.14
            weight = .semibold
        default:
            scale = 1.06
            weight = .semibold
        }
        fragment.font = Font.system(
            size: max(1, basePointSize * scale),
            weight: weight,
            design: .monospaced
        )

        // Collect ranges first; mutating during `runs` iteration is undefined.
        let ranges = fragment.runs.map(\.range)
        for range in ranges {
            var intents = fragment[range].inlinePresentationIntent ?? []
            intents.insert(.stronglyEmphasized)
            fragment[range].inlinePresentationIntent = intents
        }
    }

    private static func emphasizeInlineCode(_ attributed: inout AttributedString) {
        let codeRanges = attributed.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                return nil
            }
            return run.range
        }
        let wash = Color(red: 0, green: 217 / 255, blue: 1).opacity(0.14)
        for range in codeRanges {
            attributed[range].backgroundColor = wash
        }
    }

    private static func headerLevel(of intent: PresentationIntent?) -> Int? {
        guard let intent else { return nil }
        for component in intent.components {
            if case .header(let level) = component.kind {
                return level
            }
        }
        return nil
    }

    private static func listContext(of intent: PresentationIntent?) -> (itemID: Int, marker: String)? {
        guard let intent else { return nil }
        var depth = 0
        var isOrdered = false
        var itemID: Int?
        var ordinal = 1
        for component in intent.components {
            switch component.kind {
            case .unorderedList:
                depth += 1
                isOrdered = false
            case .orderedList:
                depth += 1
                isOrdered = true
            case .listItem(let itemOrdinal):
                itemID = component.identity
                ordinal = itemOrdinal
            default:
                break
            }
        }
        guard let itemID else { return nil }
        let indent = String(repeating: "  ", count: max(0, depth - 1))
        let glyph = isOrdered ? "\(ordinal). " : "\(unorderedListBullet) "
        return (itemID, indent + glyph)
    }

    private static func isOnlyNewlines(_ attributed: AttributedString) -> Bool {
        !attributed.characters.isEmpty && attributed.characters.allSatisfy { $0 == "\n" || $0 == "\r" }
    }

    private static func endsWithNewline(_ attributed: AttributedString) -> Bool {
        guard let last = attributed.characters.last else { return true }
        return last == "\n" || last == "\r"
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
