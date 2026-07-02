import SwiftUI
import LlamaEngine

/// Searches the web for sources via a configured provider (Settings → Web Search), shows
/// the results, and adds the ones you pick — fetching each through `WebAccess`, so
/// robots.txt and per-host rate limits are respected and each fetch reports its own status
/// (added / blocked / failed). Sanctioned-API search only; never scrapes a search engine.
struct WebSearchView: View {
    /// Called once per added source with its title and plain-text content.
    var onAdd: (_ title: String, _ content: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.searchProvider) private var searchProvider = WebSearch.ProviderKind.none.rawValue
    @AppStorage(SettingsKey.searxngURL) private var searxngURL = ""
    @AppStorage(SettingsKey.braveAPIKey) private var braveAPIKey = ""
    @AppStorage(SettingsKey.tavilyAPIKey) private var tavilyAPIKey = ""
    @AppStorage(SettingsKey.marginaliaAPIKey) private var marginaliaAPIKey = "public"

    @State private var query = ""
    @State private var results: [WebSearch.Result] = []
    @State private var selected: Set<String> = []
    @State private var status: [String: SourceStatus] = [:]
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var errorMessage: String?

    /// The search settings the app owns, assembled for the engine.
    private var searchConfig: WebSearchConfig {
        WebSearchConfig(provider: WebSearch.ProviderKind(rawValue: searchProvider) ?? .none,
                        searxngURL: searxngURL,
                        braveAPIKey: braveAPIKey,
                        tavilyAPIKey: tavilyAPIKey,
                        marginaliaAPIKey: marginaliaAPIKey)
    }
    private var providerConfigured: Bool { WebSearch.isConfigured(searchConfig) }

    private enum SourceStatus: Equatable {
        case fetching, added, skipped(String)
        var label: String {
            switch self {
            case .fetching: return "Fetching…"
            case .added: return "Added"
            case .skipped(let why): return why
            }
        }
        var isAdded: Bool { self == .added }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !providerConfigured {
                notConfigured
            } else {
                searchBar
                Divider()
                resultsList
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 640)
    }

    private var header: some View {
        HStack {
            Label("Search the Web", systemImage: "magnifyingglass").font(.headline)
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var notConfigured: some View {
        ContentUnavailableView {
            Label("No search provider", systemImage: "magnifyingglass")
        } description: {
            Text("Set up a provider in **Settings → Web Search** — Wikipedia or a self-hosted SearXNG instance (no account), the independent Marginalia engine, or a Brave / Tavily API key.")
        }
        .frame(maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack {
            TextField("Search the web…", text: $query, onCommit: runSearch)
                .textFieldStyle(.roundedBorder)
            Button(action: runSearch) {
                if isSearching { ProgressView().controlSize(.small) } else { Text("Search") }
            }
            .disabled(isSearching || query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                if results.isEmpty && errorMessage == nil {
                    Text(isSearching ? "" : "Search to find pages, then pick which to add as sources.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                ForEach(results) { result in
                    resultRow(result)
                    Divider()
                }
            }
        }
    }

    private func resultRow(_ result: WebSearch.Result) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: binding(for: result.url))
                .labelsHidden()
                .disabled(isAdding)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).fontWeight(.medium).lineLimit(2)
                Text(result.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !result.snippet.isEmpty {
                    Text(result.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if let state = status[result.url] {
                    Text(state.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(state.isAdded ? Color.green : Color.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            if !results.isEmpty {
                Button(selected.count == results.count ? "Select none" : "Select all") {
                    selected = selected.count == results.count ? [] : Set(results.map(\.url))
                }
                .buttonStyle(.borderless).font(.caption)
                .disabled(isAdding)
            }
            Spacer()
            if isAdding { ProgressView().controlSize(.small) }
            Button(action: addSelected) {
                Label(selected.isEmpty ? "Add sources" : "Add \(selected.count) source\(selected.count == 1 ? "" : "s")",
                      systemImage: "plus")
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selected.isEmpty || isAdding)
        }
        .padding()
    }

    // MARK: - Actions

    private func binding(for url: String) -> Binding<Bool> {
        Binding(get: { selected.contains(url) },
                set: { on in if on { selected.insert(url) } else { selected.remove(url) } })
    }

    private func runSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSearching else { return }
        isSearching = true
        errorMessage = nil
        results = []
        selected = []
        status = [:]
        Task {
            do {
                results = try await WebSearch.search(trimmed, config: searchConfig)
                if results.isEmpty { errorMessage = "No results." }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func addSelected() {
        let chosen = results.filter { selected.contains($0.url) }
        guard !chosen.isEmpty, !isAdding else { return }
        isAdding = true
        Task {
            for result in chosen {
                status[result.url] = .fetching
                do {
                    let (url, html) = try await WebAccess.shared.fetch(result.url)
                    let extracted = HTMLExtractor.extract(html)
                    let body = extracted.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !body.isEmpty else { status[result.url] = .skipped("No readable text"); continue }
                    let title = extracted.title.isEmpty ? result.title : extracted.title
                    onAdd(title, "Source: \(url.absoluteString)\nTitle: \(title)\n\n\(body)")
                    selected.remove(result.url)
                    status[result.url] = .added
                } catch {
                    status[result.url] = .skipped(error.localizedDescription)
                }
            }
            isAdding = false
        }
    }
}
