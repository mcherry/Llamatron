import SwiftUI

/// Inline Markdown helpers. Block structure is handled by `MarkdownParser` /
/// `MarkdownView`; this only renders the inline span of a single block (bold,
/// italic, links, inline code) into an `AttributedString`.
enum Markdown {
    static func inlineAttributed(_ raw: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        var attributed = (try? AttributedString(markdown: raw, options: options))
            ?? AttributedString(raw)

        // SwiftUI doesn't visibly style inline `code` spans on its own; give them a
        // monospaced font so `like this` stands out.
        let codeRanges = attributed.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else { return nil }
            return run.range
        }
        for range in codeRanges {
            attributed[range].font = .system(.body, design: .monospaced)
        }
        return attributed
    }
}
