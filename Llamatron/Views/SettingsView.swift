import SwiftUI

/// App-wide settings (Cmd-,). Server address plus defaults applied to new sessions.
struct SettingsView: View {
    @AppStorage(SettingsKey.serverURL) private var serverURL = SettingsDefault.serverURL
    @AppStorage(SettingsKey.defaultContextSize) private var defaultContextSize = SettingsDefault.contextSize
    @AppStorage(SettingsKey.defaultModel) private var defaultModel = ""
    @AppStorage(SettingsKey.requestTimeout) private var requestTimeout = SettingsDefault.timeout
    @AppStorage(SettingsKey.embeddingModel) private var embeddingModel = SettingsDefault.embeddingModel
    @AppStorage(SettingsKey.diagramGuidance) private var diagramGuidance = false

    @AppStorage(SettingsKey.searchProvider) private var searchProvider = WebSearch.ProviderKind.none.rawValue
    @AppStorage(SettingsKey.searxngURL) private var searxngURL = ""
    @AppStorage(SettingsKey.braveAPIKey) private var braveAPIKey = ""
    @AppStorage(SettingsKey.tavilyAPIKey) private var tavilyAPIKey = ""
    @AppStorage(SettingsKey.marginaliaAPIKey) private var marginaliaAPIKey = "public"

    @AppStorage(SettingsKey.imageGenEnabled) private var imageGenEnabled = false
    @AppStorage(SettingsKey.imageBackendKind) private var imageBackendKind = ImageBackendKind.easyDiffusion.rawValue
    @AppStorage(SettingsKey.imageServerURL) private var imageServerURL = SettingsDefault.imageServerURL
    @AppStorage(SettingsKey.imageModel) private var imageModel = ""
    @AppStorage(SettingsKey.imageSteps) private var imageSteps = SettingsDefault.imageSteps
    @AppStorage(SettingsKey.imageSize) private var imageSize = SettingsDefault.imageSize
    @AppStorage(SettingsKey.imageCFG) private var imageCFG = SettingsDefault.imageCFG
    @AppStorage(SettingsKey.imageNegativePrompt) private var imageNegativePrompt = ""

    @State private var allModels: [OllamaModel] = []
    @State private var loadingModels = false
    @State private var showingModelManager = false

    @State private var imageModels: [ImageModel] = []
    @State private var imageTesting = false
    @State private var imageTestStatus: String?
    @State private var imageTestOK = false

    private var chatModels: [OllamaModel] {
        allModels.filter { !$0.isEmbeddingModel }
    }

    /// Embedding-model names for the retrieval picker, always including the current
    /// selection and the default so the value is never orphaned.
    private var embeddingChoices: [String] {
        var names = Set(allModels.filter(\.isEmbeddingModel).map(\.name))
        names.insert(SettingsDefault.embeddingModel)
        names.insert(embeddingModel)
        return names.sorted()
    }

    var body: some View {
        Form {
            Section {
                ServerSettingsForm()
            }
            Section("Defaults for New Sessions") {
                Picker("Default model", selection: $defaultModel) {
                    Text("None").tag("")
                    ForEach(chatModels) { model in
                        Text(model.name).tag(model.name)
                    }
                    if !defaultModel.isEmpty,
                       !chatModels.contains(where: { $0.name == defaultModel }) {
                        Text(defaultModel).tag(defaultModel)
                    }
                }
                Picker("Context size", selection: $defaultContextSize) {
                    ForEach(ContextSize.presets, id: \.self) { size in
                        Text(ContextSize.label(size)).tag(size)
                    }
                }
            }
            Section("Network") {
                Picker("Request timeout", selection: $requestTimeout) {
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("120 seconds").tag(120)
                    Text("300 seconds").tag(300)
                }
            }
            Section("Models") {
                Button {
                    showingModelManager = true
                } label: {
                    Label("Manage Models…", systemImage: "shippingbox")
                }
                Text("Pull new models, see what's loaded, and free space by deleting models on the server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Attached Files") {
                Picker("Embedding model", selection: $embeddingModel) {
                    ForEach(embeddingChoices, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Text("Used to find relevant excerpts in attached files (retrieval). Pick an embedding model available on your server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Web Search") {
                Picker("Provider", selection: $searchProvider) {
                    ForEach(WebSearch.ProviderKind.allCases) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                if searchProvider == WebSearch.ProviderKind.wikipedia.rawValue {
                    Text("Searches English Wikipedia — no account needed. Great for history, places, and general facts.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if searchProvider == WebSearch.ProviderKind.searxng.rawValue {
                    TextField("SearXNG instance URL", text: $searxngURL)
                    Text("A self-hosted SearXNG base URL (e.g. http://localhost:8080) — no account needed; it aggregates real engines.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if searchProvider == WebSearch.ProviderKind.marginalia.rawValue {
                    TextField("Marginalia API key", text: $marginaliaAPIKey)
                    Text("An independent engine for text-heavy, non-commercial pages. The default “public” key works (shared rate limit); email contact@marginalia-search.com for a free personal key.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if searchProvider == WebSearch.ProviderKind.brave.rawValue {
                    SecureField("Brave Search API key", text: $braveAPIKey)
                    Text("From the Brave Search API dashboard. Stored locally in app settings.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if searchProvider == WebSearch.ProviderKind.tavily.rawValue {
                    SecureField("Tavily API key", text: $tavilyAPIKey)
                    Text("An LLM-focused search API with a free tier, from tavily.com. Stored locally in app settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Find web pages to add as context sources from the globe button in the composer. Search uses sanctioned APIs only (never scraping); result pages are fetched politely — robots.txt and per-host rate limits apply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Image Generation") {
                Toggle("Enable image generation", isOn: $imageGenEnabled)
                Text("Generate images from a local image server (e.g. Easy Diffusion) by setting a chat's backend to Image Generation. Optional.")
                    .font(.caption).foregroundStyle(.secondary)
                if imageGenEnabled {
                    Picker("Server type", selection: $imageBackendKind) {
                        ForEach(ImageBackendKind.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    TextField("Server URL", text: $imageServerURL)
                        .autocorrectionDisabled()
                    HStack(spacing: 8) {
                        Button("Test") { Task { await testImageServer() } }
                            .disabled(imageTesting || imageServerURL.isEmpty)
                        if imageTesting { ProgressView().controlSize(.small) }
                        if let status = imageTestStatus {
                            Label(status, systemImage: imageTestOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(imageTestOK ? .green : .red)
                                .font(.caption).lineLimit(2)
                        }
                    }
                    Picker("Default model", selection: $imageModel) {
                        Text("None").tag("")
                        ForEach(imageModels) { Text($0.name).tag($0.id) }
                        if !imageModel.isEmpty, !imageModels.contains(where: { $0.id == imageModel }) {
                            Text(imageModel).tag(imageModel)
                        }
                    }
                    Text("Run Test to load the server's models, then pick a default.")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper("Steps: \(imageSteps)", value: $imageSteps, in: 1...150)
                    Stepper("Size: \(imageSize)px", value: $imageSize, in: 256...2048, step: 64)
                    Stepper(value: $imageCFG, in: 1...20, step: 0.5) {
                        Text("Guidance (CFG): \(imageCFG, specifier: "%.1f")")
                    }
                    TextField("Negative prompt (optional)", text: $imageNegativePrompt, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            Section("Rendering") {
                Toggle("Guide models to render diagrams inline", isOn: $diagramGuidance)
                Text("Adds a short system instruction so models emit valid Mermaid diagrams (quoted labels) and skip “paste into an online editor” notes. Diagrams render inline in the chat. Appears in the request payload, visible in the turn inspector.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .task { await loadModels() }
        .sheet(isPresented: $showingModelManager) {
            ModelManagementView(serverURL: serverURL)
        }
    }

    private func loadModels() async {
        guard let client = OllamaClient(baseURLString: serverURL) else { return }
        loadingModels = true
        if let fetched = try? await client.models() {
            allModels = fetched.sorted { $0.name < $1.name }
        }
        loadingModels = false
    }

    /// Tests the configured image server by listing its models and populating the default-model
    /// picker. Selects the first model if none is chosen yet.
    private func testImageServer() async {
        imageTesting = true
        imageTestStatus = nil
        let kind = ImageBackendKind(rawValue: imageBackendKind) ?? .easyDiffusion
        let provider = kind.makeProvider(baseURLString: imageServerURL)
        do {
            let models = try await provider.listModels().sorted { $0.name < $1.name }
            imageModels = models
            imageTestOK = !models.isEmpty
            imageTestStatus = models.isEmpty
                ? "Connected, but found no image models."
                : "Found \(models.count) model\(models.count == 1 ? "" : "s")."
            if imageModel.isEmpty, let first = models.first { imageModel = first.id }
        } catch {
            imageTestOK = false
            imageTestStatus = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach the server."
        }
        imageTesting = false
    }
}
