import SwiftUI
import LlamaEngine

/// A curated catalog of the search providers the app supports. Set up credentials for any of
/// them (keys are shared with the Web Search settings and the search sheet), see which are
/// ready, and jump to each provider's signup / docs. Only the providers built into the app
/// appear — you configure the supported ones, you can't add arbitrary search APIs.
struct SearchProviderManagerView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.searxngURL) private var searxngURL = ""
    @AppStorage(SettingsKey.braveAPIKey) private var braveAPIKey = ""
    @AppStorage(SettingsKey.tavilyAPIKey) private var tavilyAPIKey = ""
    @AppStorage(SettingsKey.exaAPIKey) private var exaAPIKey = ""
    @AppStorage(SettingsKey.linkupAPIKey) private var linkupAPIKey = ""
    @AppStorage(SettingsKey.tinyfishAPIKey) private var tinyfishAPIKey = ""
    @AppStorage(SettingsKey.marginaliaAPIKey) private var marginaliaAPIKey = "public"

    /// The credentials assembled so we can compute each provider's readiness.
    private var config: WebSearchConfig {
        WebSearchConfig(searxngURL: searxngURL,
                        braveAPIKey: braveAPIKey,
                        tavilyAPIKey: tavilyAPIKey,
                        exaAPIKey: exaAPIKey,
                        linkupAPIKey: linkupAPIKey,
                        tinyfishAPIKey: tinyfishAPIKey,
                        marginaliaAPIKey: marginaliaAPIKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                ForEach(WebSearch.catalog) { provider in
                    Section { providerRow(provider) }
                }
                Section {
                    Text("Only the providers built into the app are shown — you can configure the ones you want, but you can't add arbitrary search APIs. Keys are stored locally in app settings and shared with the search sheet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 480, height: 640)
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Search Providers").font(.headline)
                Text("Set up the engines you want to use").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding()
    }

    @ViewBuilder
    private func providerRow(_ provider: WebSearch.ProviderKind) -> some View {
        let ready = WebSearch.isReady(provider, config: config)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(ready ? Color.green : Color.secondary)
                Text(provider.label).font(.headline)
                Spacer()
                Text(readinessLabel(provider, ready: ready))
                    .font(.caption)
                    .foregroundStyle(ready ? Color.green : Color.secondary)
            }
            Text(provider.summary).font(.caption).foregroundStyle(.secondary)
            credentialField(provider)
            linksRow(provider)
        }
        .padding(.vertical, 4)
    }

    private func readinessLabel(_ provider: WebSearch.ProviderKind, ready: Bool) -> String {
        if ready { return "Ready" }
        return provider.credentialKind == .instanceURL ? "Needs a URL" : "Needs a key"
    }

    @ViewBuilder
    private func credentialField(_ provider: WebSearch.ProviderKind) -> some View {
        switch provider.credentialKind {
        case .none:
            EmptyView()
        case .instanceURL:
            TextField("Instance URL (e.g. http://localhost:8080)", text: binding(for: provider))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        case .apiKey:
            SecureField("API key", text: binding(for: provider))
                .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private func linksRow(_ provider: WebSearch.ProviderKind) -> some View {
        HStack(spacing: 14) {
            if let signup = provider.signupURL, let url = URL(string: signup) {
                Link(destination: url) { Label("Get a key", systemImage: "key") }
            }
            if let docs = provider.docsURL, let url = URL(string: docs) {
                Link(destination: url) { Label("Docs", systemImage: "book") }
            }
        }
        .font(.caption)
    }

    /// Maps a provider to its stored credential (URL or API key). Keyless providers get a
    /// throwaway binding since their field never renders.
    private func binding(for provider: WebSearch.ProviderKind) -> Binding<String> {
        switch provider {
        case .searxng: return $searxngURL
        case .brave: return $braveAPIKey
        case .tavily: return $tavilyAPIKey
        case .exa: return $exaAPIKey
        case .linkup: return $linkupAPIKey
        case .tinyfish: return $tinyfishAPIKey
        case .marginalia: return $marginaliaAPIKey
        case .none, .wikipedia: return .constant("")
        }
    }
}
