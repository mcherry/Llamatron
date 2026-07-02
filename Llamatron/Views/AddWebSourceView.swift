import SwiftUI
import LlamaEngine

/// Adds a source to the current session: fetch a **web page** (hardened, manual fetch →
/// readability-lite plain text) or **paste text** directly. The result is handed back as a
/// titled block of plain text — the caller stores it as an attachment so the existing
/// retrieval pipeline can use it. If a fetch is blocked or paywalled, the error nudges the
/// user to paste the text instead, so adding a source never hard-fails. Presented as a sheet.
struct AddWebSourceView: View {
    /// Called with a source title and its plain-text content.
    var onAdd: (_ title: String, _ content: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .web
    @State private var urlText = ""
    @State private var pastedTitle = ""
    @State private var pastedText = ""
    @State private var isFetching = false
    @State private var errorMessage: String?

    private enum Mode: String, CaseIterable, Identifiable {
        case web, text
        var id: String { rawValue }
        var label: String { self == .web ? "Web page" : "Paste text" }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Source", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if mode == .web { webFields } else { textFields }

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding()
            }
            Divider()
            footer
        }
        .frame(width: 540, height: 480)
    }

    private var header: some View {
        HStack {
            Label("Add Source", systemImage: "doc.text.magnifyingglass").font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var webFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Page address").font(.caption).foregroundStyle(.secondary)
            TextField("https://example.com/article", text: $urlText, onCommit: fetch)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
            Text("The page is fetched once and reduced to plain text. Its content is treated as untrusted reference material — never as instructions.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private var textFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title (optional)", text: $pastedTitle)
                .textFieldStyle(.roundedBorder)
            Text("Text").font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $pastedText)
                .font(.body)
                .frame(minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
        }
    }

    private var footer: some View {
        HStack {
            if isFetching {
                ProgressView().controlSize(.small)
                Text("Fetching…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: add) {
                Label(mode == .web ? "Fetch & Add" : "Add", systemImage: "plus")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!canAdd)
        }
        .padding()
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout).foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var canAdd: Bool {
        if isFetching { return false }
        return mode == .web
            ? !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func add() {
        switch mode {
        case .web: fetch()
        case .text:
            let body = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            let title = pastedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = title.isEmpty ? "Pasted note" : title
            onAdd(name, "Source: pasted text\nTitle: \(name)\n\n\(body)")
            dismiss()
        }
    }

    private func fetch() {
        guard !isFetching else { return }
        isFetching = true
        errorMessage = nil
        Task {
            do {
                let (url, html) = try await WebAccess.shared.fetch(urlText)
                let extracted = HTMLExtractor.extract(html)
                let body = extracted.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !body.isEmpty else {
                    errorMessage = "No readable text was found on that page. Try pasting the text instead."
                    isFetching = false
                    return
                }
                let title = extracted.title.isEmpty ? (url.host ?? urlText) : extracted.title
                onAdd(title, "Source: \(url.absoluteString)\nTitle: \(title)\n\n\(body)")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isFetching = false
            }
        }
    }
}
