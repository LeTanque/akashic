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
        let source = protectLiteralWhitespace(
            applySoftLineBreaks(normalizeSmartTypography(markdown))
        )
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

    /// CommonMark collapses runs of spaces in paragraphs; protect intentional spacing before parse.
    static func protectLiteralWhitespace(_ markdown: String) -> String {
        var output: [String] = []
        var inFence = false
        for lineSub in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(lineSub)
            let trimmedFence = line.trimmingCharacters(in: .whitespaces)
            if inFence {
                output.append(line)
                if trimmedFence.hasPrefix("```") || trimmedFence.hasPrefix("~~~") {
                    inFence = false
                }
                continue
            }
            if trimmedFence.hasPrefix("```") || trimmedFence.hasPrefix("~~~") {
                inFence = true
                output.append(line)
                continue
            }
            output.append(transformLinePreservingSpaces(line))
        }
        return output.joined(separator: "\n")
    }

    private static func startsWithBlockMarker(_ rest: ArraySlice<Character>) -> Bool {
        guard let first = rest.first else { return false }
        let afterFirst = rest.dropFirst().first
        if "-*+".contains(first) || first == "\u{2013}" || first == "\u{2014}" {
            return afterFirst == " "
        }
        if first == ">" { return true }
        if first.isNumber {
            let digits = rest.prefix { $0.isNumber }
            let next = rest.dropFirst(digits.count)
            return (next.first == "." || next.first == ")") && next.dropFirst().first == " "
        }
        return false
    }

    private static func transformLinePreservingSpaces(_ line: String) -> String {
        var chars = Array(line)
        var index = 0
        while index < chars.count, chars[index] == " " {
            index += 1
        }
        // Indented list items and quotes are structural (nesting); only protect plain-text indent.
        if !startsWithBlockMarker(chars[index...]) {
            for k in 0..<index { chars[k] = "\u{00A0}" }
        }
        var i = index
        while i < chars.count {
            if chars[i] == " " {
                var run = 1
                var j = i + 1
                while j < chars.count, chars[j] == " " {
                    run += 1
                    j += 1
                }
                if run >= 2 {
                    for k in i..<j {
                        chars[k] = "\u{00A0}"
                    }
                }
                i = j
            } else {
                i += 1
            }
        }
        return String(chars)
    }

    /// GitHub-style soft breaks: a single newline inside a paragraph becomes a visible line break.
    static func applySoftLineBreaks(_ markdown: String) -> String {
        var lines: [String] = []
        var inFence = false
        for lineSub in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(lineSub)
            let trimmedFence = line.trimmingCharacters(in: .whitespaces)
            if inFence {
                lines.append(line)
                if trimmedFence.hasPrefix("```") || trimmedFence.hasPrefix("~~~") {
                    inFence = false
                }
                continue
            }
            if trimmedFence.hasPrefix("```") || trimmedFence.hasPrefix("~~~") {
                inFence = true
                lines.append(line)
                continue
            }
            lines.append(line)
        }

        var output: [String] = []
        output.reserveCapacity(lines.count)
        for index in lines.indices {
            var line = lines[index]
            if index + 1 < lines.count, shouldSoftBreak(after: line, before: lines[index + 1], inFence: false) {
                // Backslash hard break: trailing double spaces would be eaten by
                // protectLiteralWhitespace (which turns runs of spaces into NBSPs).
                if line.last != "\\" {
                    line += "\\"
                }
            }
            output.append(line)
        }
        return output.joined(separator: "\n")
    }

    private static func shouldSoftBreak(after line: String, before nextLine: String, inFence: Bool) -> Bool {
        guard !inFence else { return false }
        guard !line.isEmpty, !nextLine.isEmpty else { return false }
        guard !lineStartsBlock(line), !lineStartsBlock(nextLine) else { return false }
        return true
    }

    private static func lineStartsBlock(_ line: String) -> Bool {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        let rest = line[index...]
        guard !rest.isEmpty else { return false }
        let trimmedFence = line.trimmingCharacters(in: .whitespaces)
        if trimmedFence.hasPrefix("```") || trimmedFence.hasPrefix("~~~") { return true }
        if rest.first == "#" {
            var hashCount = 0
            var cursor = rest.startIndex
            while cursor < rest.endIndex, rest[cursor] == "#" {
                hashCount += 1
                cursor = rest.index(after: cursor)
            }
            if hashCount <= 6, cursor < rest.endIndex, rest[cursor] == " " {
                return true
            }
        }
        return startsWithBlockMarker(ArraySlice(rest))
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
        var previousBlockBoundary: BlockBoundary?

        for run in source.runs {
            var fragment = AttributedString(source[run.range])
            let intent = run.presentationIntent
            let blockBoundary = blockBoundary(of: intent)

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
                previousBlockBoundary = nil
            } else {
                if emittedMarkerForItem == nil,
                   let blockBoundary,
                   blockBoundary != previousBlockBoundary {
                    insertBlockGap(into: &output, before: fragment)
                }
                emittedMarkerForItem = nil
                if blockBoundary != nil {
                    previousBlockBoundary = blockBoundary
                }
            }

            output += fragment
        }

        return output
    }

    private enum BlockBoundary: Equatable {
        case paragraph(Int)
        case header(Int)
    }

    private static func insertBlockGap(into output: inout AttributedString, before fragment: AttributedString) {
        guard !output.characters.isEmpty else { return }
        if endsWithNewline(output) { return }
        if startsWithNewline(fragment) { return }
        output += AttributedString("\n\n")
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

    private static func startsWithNewline(_ attributed: AttributedString) -> Bool {
        guard let first = attributed.characters.first else { return true }
        return first == "\n" || first == "\r"
    }

    private static func blockBoundary(of intent: PresentationIntent?) -> BlockBoundary? {
        guard let intent else { return nil }
        var headerIdentity: Int?
        var paragraphIdentity: Int?
        for component in intent.components {
            switch component.kind {
            case .header:
                headerIdentity = component.identity
            case .paragraph:
                paragraphIdentity = component.identity
            default:
                break
            }
        }
        if let headerIdentity {
            return .header(headerIdentity)
        }
        if let paragraphIdentity {
            return .paragraph(paragraphIdentity)
        }
        return nil
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
