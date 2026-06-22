import Foundation

/// A block-level element parsed from Markdown text. Inline styling (bold, italic,
/// links, inline code) is handled when each block is rendered; this enum only
/// captures block structure. `Equatable` so the parser can be unit-tested.
enum MarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case codeBlock(language: String?, code: String)
    case unorderedList([String])
    case orderedList([String])
    case quote([String])
    case horizontalRule
}

/// A small, dependency-free block-level Markdown parser tuned for LLM replies:
/// fenced code blocks (the important one), headings, ordered/unordered lists,
/// block quotes, horizontal rules, and paragraphs. Pure and synchronous so it can
/// be unit-tested, and tolerant of partial input (e.g. an unclosed code fence while
/// a reply is still streaming).
enum MarkdownParser {
    static func parse(_ raw: String) -> [MarkdownBlock] {
        let lines = raw.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            // Fenced code block. An unterminated fence runs to the end of the text,
            // so streaming code renders as code immediately.
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var code: [String] = []
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    code.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language.isEmpty ? nil : language,
                                         code: code.joined(separator: "\n")))
                continue
            }

            if line.isEmpty { i += 1; continue }

            if isHorizontalRule(line) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            if let heading = heading(line) {
                blocks.append(heading)
                i += 1
                continue
            }

            if isUnordered(line) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isUnordered(t) else { break }
                    items.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }

            if orderedContent(line) != nil {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let content = orderedContent(t) else { break }
                    items.append(content)
                    i += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            if line.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quoteLines.append(String(t.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quoteLines))
                continue
            }

            // Paragraph: gather consecutive lines until a blank line or a new block.
            var paragraph: [String] = []
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if startsBlock(t) { break }
                paragraph.append(lines[i])
                i += 1
            }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return blocks
    }

    // MARK: - Line classification

    /// Whether `line` (already trimmed) begins a non-paragraph block, used to know
    /// where a paragraph ends.
    private static func startsBlock(_ line: String) -> Bool {
        line.isEmpty
            || line.hasPrefix("```")
            || isHorizontalRule(line)
            || heading(line) != nil
            || isUnordered(line)
            || orderedContent(line) != nil
            || line.hasPrefix(">")
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#" {
            level += 1
            if level > 6 { return nil }
            idx = line.index(after: idx)
        }
        guard level > 0, idx < line.endIndex, line[idx] == " " else { return nil }
        let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    private static func isUnordered(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    /// Returns the content of an ordered-list item (`1. foo` → `foo`), or `nil`.
    private static func orderedContent(_ line: String) -> String? {
        var idx = line.startIndex
        var digits = 0
        while idx < line.endIndex, line[idx].isNumber {
            idx = line.index(after: idx)
            digits += 1
        }
        guard digits > 0, idx < line.endIndex, line[idx] == "." else { return nil }
        let afterDot = line.index(after: idx)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" }
            || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }
}
