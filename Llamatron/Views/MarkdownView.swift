import SwiftUI

/// Renders Markdown text as a stack of native SwiftUI views: headings, paragraphs,
/// fenced code blocks (monospaced, horizontally scrollable, with a copy button),
/// ordered/unordered lists, block quotes, and rules. Inline styling within each
/// block comes from `Markdown.inlineAttributed`.
struct MarkdownView: View {
    let text: String
    /// When true, ` ```mermaid ` blocks render as diagrams. Disabled while a reply is
    /// still streaming (the fence isn't closed yet), so they show as source until done.
    var renderDiagrams: Bool = true

    var body: some View {
        let blocks = MarkdownParser.parse(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Markdown.inlineAttributed(text))
                .font(headingFont(level))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph(let text):
            Text(Markdown.inlineAttributed(text))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .codeBlock(let language, let code):
            if renderDiagrams, language?.lowercased() == "mermaid" {
                MermaidView(source: code)
            } else {
                CodeBlockView(language: language, code: code)
            }

        case .unorderedList(let items):
            listView(rows: items.map { (marker: "•", text: $0) })

        case .orderedList(let items):
            listView(rows: items.enumerated().map { (marker: "\($0.offset + 1).", text: $0.element) })

        case .quote(let lines):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.secondary)
                    .frame(width: 3)
                Text(Markdown.inlineAttributed(lines.joined(separator: "\n")))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows)

        case .horizontalRule:
            Divider()
        }
    }

    private func listView(rows: [(marker: String, text: String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.marker)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(Markdown.inlineAttributed(row.text))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline
        default: return .body.bold()
        }
    }
}

/// A fenced code block: optional language label, a copy-on-hover button, and the
/// code in a monospaced font that scrolls horizontally instead of wrapping.
private struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text((language?.isEmpty == false ? language! : "code").lowercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Pasteboard.copy(code)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy code")
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        .onHover { hovering = $0 }
    }
}

/// Renders a GFM pipe table as an aligned grid: a shaded header row and bordered
/// cells. Cell text supports inline Markdown and wraps within its column.
private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    cell(header, isHeader: true)
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        cell(value, isHeader: false)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        Text(Markdown.inlineAttributed(text))
            .font(isHeader ? .body.weight(.semibold) : .body)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isHeader ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            .overlay(
                Rectangle()
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}
