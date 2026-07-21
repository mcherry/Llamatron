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
    @AppStorage(SettingsKey.exaAPIKey) private var exaAPIKey = ""
    @AppStorage(SettingsKey.linkupAPIKey) private var linkupAPIKey = ""
    @AppStorage(SettingsKey.tinyfishAPIKey) private var tinyfishAPIKey = ""
    @AppStorage(SettingsKey.marginaliaAPIKey) private var marginaliaAPIKey = "public"
    @AppStorage(SettingsKey.metaDisabledProviders) private var metaDisabledProviders = ""

    @State private var query = ""
    @State private var results: [WebSearch.Result] = []
    @State private var selected: Set<String> = []
    @State private var status: [String: SourceStatus] = [:]
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var errorMessage: String?
    /// Pagination: the offset to request for the next page, and whether more remain.
    @State private var nextOffset = 0
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var providerOutcomes: [WebSearch.ProviderOutcome] = []
    @FocusState private var searchFieldFocused: Bool

    /// The search settings the app owns, assembled for the engine.
    private var searchConfig: WebSearchConfig {
        WebSearchConfig(provider: WebSearch.ProviderKind(rawValue: searchProvider) ?? .none,
                        searxngURL: searxngURL,
                        braveAPIKey: braveAPIKey,
                        tavilyAPIKey: tavilyAPIKey,
                        exaAPIKey: exaAPIKey,
                        linkupAPIKey: linkupAPIKey,
                        tinyfishAPIKey: tinyfishAPIKey,
                        marginaliaAPIKey: marginaliaAPIKey,
                        enabledProviders: WebSearchSettings.enabledProviders(disabledCSV: metaDisabledProviders))
    }
    private var providerConfigured: Bool { WebSearch.isConfigured(searchConfig) }

    /// Display name of the active provider (e.g. "Wikipedia"), shown in the header.
    private var providerLabel: String {
        (WebSearch.ProviderKind(rawValue: searchProvider) ?? .none).label
    }

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
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search the Web").font(.headline)
                    if providerConfigured {
                        Text("via \(providerLabel)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "magnifyingglass")
            }
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
                .focused($searchFieldFocused)
            Button(action: runSearch) {
                if isSearching { ProgressView().controlSize(.small) } else { Text("Search") }
            }
            .disabled(isSearching || query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .onAppear {
            DispatchQueue.main.async { searchFieldFocused = true }
        }
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
                skippedEnginesNotice
                if results.isEmpty && errorMessage == nil && !providerOutcomes.contains(where: \.failed) {
                    Text(isSearching ? "" : "Search to find pages, then pick which to add as sources.")
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                ForEach(results) { result in
                    resultRow(result)
                    Divider()
                }
                if canLoadMore {
                    Button(action: loadMore) {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("More results", systemImage: "arrow.down.circle")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                    .disabled(isLoadingMore || isAdding)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    /// A one-line warning listing the engines Meta-search couldn't use this run, with why.
    @ViewBuilder
    private var skippedEnginesNotice: some View {
        let failed = providerOutcomes.filter(\.failed)
        if !failed.isEmpty {
            let detail = failed.map { "\($0.provider.label) (\($0.failureReason?.label ?? "unavailable"))" }
                               .joined(separator: ", ")
            Label("Skipped \(failed.count) engine\(failed.count == 1 ? "" : "s"): \(detail)",
                  systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal).padding(.vertical, 8)
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
        nextOffset = 0
        canLoadMore = false
        providerOutcomes = []
        Task {
            do {
                let page = try await WebSearch.search(trimmed, config: searchConfig)
                results = page.results
                nextOffset = page.nextOffset
                canLoadMore = page.hasMore
                providerOutcomes = page.providerOutcomes
                if results.isEmpty && !page.providerOutcomes.contains(where: \.failed) {
                    errorMessage = "No results."
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    /// Fetches the next page and appends it, de-duplicating by URL so already-checked
    /// results keep their selection (selection and status are keyed by URL).
    private func loadMore() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canLoadMore, !isSearching, !isLoadingMore else { return }
        isLoadingMore = true
        Task {
            do {
                let page = try await WebSearch.search(trimmed, offset: nextOffset, config: searchConfig)
                let existing = Set(results.map(\.url))
                results.append(contentsOf: page.results.filter { !existing.contains($0.url) })
                nextOffset = page.nextOffset
                canLoadMore = page.hasMore
            } catch {
                errorMessage = error.localizedDescription
                canLoadMore = false
            }
            isLoadingMore = false
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
