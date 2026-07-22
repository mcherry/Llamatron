import SwiftUI
import LlamaEngine
import LlamaEngineStore
#if os(macOS)
import AppKit
#endif
import UniformTypeIdentifiers

/// App-wide settings (Cmd-,). Server address plus defaults applied to new sessions.
struct SettingsView: View {
    @AppStorage(SettingsKey.serverURL) private var serverURL = SettingsDefault.serverURL
    @AppStorage(SettingsKey.llamaServerURL) private var llamaServerURL = SettingsDefault.llamaServerURL
    @AppStorage(SettingsKey.defaultContextSize) private var defaultContextSize = SettingsDefault.contextSize
    @AppStorage(SettingsKey.defaultModel) private var defaultModel = ""
    @AppStorage(SettingsKey.defaultBackend) private var defaultBackend = SettingsDefault.defaultBackend
    @AppStorage(SettingsKey.requestTimeout) private var requestTimeout = SettingsDefault.timeout
    @AppStorage(SettingsKey.diagramGuidance) private var diagramGuidance = false
    @AppStorage(SettingsKey.rightSizeContext) private var rightSizeContext = SettingsDefault.rightSizeContext
    @AppStorage(SettingsKey.keepAliveMinutes) private var keepAliveMinutes = SettingsDefault.keepAliveMinutes

    @AppStorage(SettingsKey.ttsFeatureEnabled) private var ttsFeatureEnabled = SettingsDefault.ttsFeatureEnabled
    @AppStorage(SettingsKey.sttFeatureEnabled) private var sttFeatureEnabled = SettingsDefault.sttFeatureEnabled
    @AppStorage(SettingsKey.webSearchEnabled) private var webSearchEnabled = SettingsDefault.webSearchEnabled
    @AppStorage(SettingsKey.toolsFeatureEnabled) private var toolsFeatureEnabled = SettingsDefault.toolsFeatureEnabled
    @AppStorage(SettingsKey.toolsAllowLocalNetwork) private var toolsAllowLocalNetwork = SettingsDefault.toolsAllowLocalNetwork
    @AppStorage(SettingsKey.searchProvider) private var searchProvider = WebSearch.ProviderKind.none.rawValue
    @AppStorage(SettingsKey.searxngURL) private var searxngURL = ""
    @AppStorage(SettingsKey.braveAPIKey) private var braveAPIKey = ""
    @AppStorage(SettingsKey.tavilyAPIKey) private var tavilyAPIKey = ""
    @AppStorage(SettingsKey.exaAPIKey) private var exaAPIKey = ""
    @AppStorage(SettingsKey.linkupAPIKey) private var linkupAPIKey = ""
    @AppStorage(SettingsKey.tinyfishAPIKey) private var tinyfishAPIKey = ""
    @AppStorage(SettingsKey.marginaliaAPIKey) private var marginaliaAPIKey = ""
    @AppStorage(SettingsKey.metaDisabledProviders) private var metaDisabledProviders = ""
    @AppStorage(SettingsKey.metaMode) private var metaMode = WebSearch.MetaSearchMode.comprehensive.rawValue

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
    @State private var showingProviderManager = false

    @State private var imageModels: [ImageModel] = []
    @State private var imageTesting = false
    @State private var imageTestStatus: String?
    @State private var imageTestOK = false

    @AppStorage(SettingsKey.comfyTemplates) private var comfyTemplatesJSON = "[]"
    @AppStorage(SettingsKey.sessionPresets) private var sessionPresetsJSON = "[]"
    @AppStorage(SettingsKey.defaultPresetID) private var defaultPresetID = ""
    @State private var comfyImportStatus: String?

    @AppStorage(SettingsKey.ttsEngine) private var ttsEngine = TTSEngine.apple.rawValue
    @AppStorage(SettingsKey.ttsAppleVoice) private var ttsAppleVoice = ""
    @AppStorage(SettingsKey.ttsServerURL) private var ttsServerURL = SettingsDefault.ttsServerURL
    @AppStorage(SettingsKey.ttsVoice) private var ttsVoice = ""
    @AppStorage(SettingsKey.ttsSpeed) private var ttsSpeed = SettingsDefault.ttsSpeed
    @AppStorage(SettingsKey.dictationAutoSend) private var dictationAutoSend = false
    @AppStorage(SettingsKey.dictationPauseSeconds) private var dictationPauseSeconds = SettingsDefault.dictationPauseSeconds
    @AppStorage(SettingsKey.conversationMode) private var conversationMode = false
    @AppStorage(SettingsKey.dictationVoiceProcessing) private var voiceProcessing = SettingsDefault.dictationVoiceProcessing
    @State private var appleVoices: [TTSVoice] = []
    @State private var ttsVoices: [TTSVoice] = []
    @State private var ttsTesting = false
    @State private var ttsTestStatus: String?
    @State private var ttsTestOK = false

    @AppStorage("settings.configuringBackend") private var configuringBackendRaw = ""
    @State private var backendTesting = false
    @State private var backendTestStatus: String?
    @State private var backendTestOK = false

    private var chatModels: [OllamaModel] {
        allModels.filter { !$0.isEmbeddingModel }
    }

    var body: some View {
        Form {
            backendsSection
            Section("New chats") {
                Picker("Start from", selection: $defaultPresetID) {
                    Text("App defaults").tag("")
                    ForEach(sessionPresets) { Text($0.name).tag($0.id) }
                }
                if defaultPresetID.isEmpty {
                    Picker("Backend", selection: $defaultBackend) {
                        ForEach(configurableBackends) { kind in
                            Text(kind.label).tag(kind.rawValue)
                        }
                    }
                    if defaultBackendKind == .ollama {
                        Picker("Model", selection: $defaultModel) {
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
                }
                Text(newChatsNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !sessionPresets.isEmpty {
                    ForEach(sessionPresets) { preset in
                        HStack {
                            Text(preset.name)
                            if preset.id == defaultPresetID {
                                Text("Default").font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                            Spacer()
                            Button(role: .destructive) { deletePreset(preset) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete this preset")
                        }
                    }
                }
            }
            Section("Network") {
                Picker("Request timeout", selection: $requestTimeout) {
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("10 minutes").tag(600)
                    Text("20 minutes").tag(1200)
                    Text("30 minutes").tag(1800)
                    Text("1 hour").tag(3600)
                }
                Text("How long to wait for a server response before giving up. Raise it for slow local models, long reasoning, or image generation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Web Search") {
                Toggle("Enable web search", isOn: $webSearchEnabled)
                if webSearchEnabled {
                Picker("Provider", selection: $searchProvider) {
                    ForEach(WebSearch.ProviderKind.allCases) { kind in
                        Text(kind.label).tag(kind.rawValue)
                    }
                }
                if let selected = WebSearch.ProviderKind(rawValue: searchProvider), selected != .none {
                    let ready = providerReady(selected)
                    Label {
                        Text(ready ? "\(selected.label) is ready."
                                   : "\(selected.label) needs setup — open Manage Providers.")
                    } icon: {
                        Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ready ? Color.green : Color.orange)
                    }
                    .font(.caption)
                    Text(selected.summary).font(.caption).foregroundStyle(.secondary)
                    if selected == .meta {
                        let engines = WebSearch.metaProviders(config: webSearchConfig)
                        Text(engines.isEmpty
                             ? "No engines enabled — turn some on in Manage Providers."
                             : "Uses: " + engines.map(\.label).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Mode", selection: $metaMode) {
                            ForEach(WebSearch.MetaSearchMode.allCases) { mode in
                                Text(mode.label).tag(mode.rawValue)
                            }
                        }
                        if let mode = WebSearch.MetaSearchMode(rawValue: metaMode) {
                            Text(mode.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Manage Providers…") { showingProviderManager = true }
                    .sheet(isPresented: $showingProviderManager) { SearchProviderManagerView() }
                Text("Set up API keys and choose an engine in Manage Providers. Search uses sanctioned APIs only (never scraping); result pages are fetched politely — robots.txt and per-host rate limits apply.")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Tools") {
                Toggle("Enable tool calling", isOn: $toolsFeatureEnabled)
                if toolsFeatureEnabled {
                    Toggle("Allow fetching local & LAN addresses", isOn: $toolsAllowLocalNetwork)
                    Text("Lets the fetch-a-page tool reach localhost and private addresses, e.g. to read a local server. Turn off to restrict it to public sites.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Let capable models call local tools during a reply — the clock, weather, web search, fetching a page, and searching this chat's attachments. Off by default. Tools run on your device, never on the server. Each chat opts in per tool in Session Settings, and anything past a pure calculation asks you to approve before it runs — the model proposes, you dispose.")
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
                    if imageBackendKind == ImageBackendKind.comfyUI.rawValue {
                        comfyTemplatesView
                    }
                }
            }
            Section("Text-to-Speech") {
                Toggle("Enable text-to-speech", isOn: $ttsFeatureEnabled)
                if ttsFeatureEnabled {
                Picker("Engine", selection: $ttsEngine) {
                    ForEach(TTSEngine.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if ttsEngine == TTSEngine.apple.rawValue {
                    Picker("Voice", selection: $ttsAppleVoice) {
                        Text("System default").tag("")
                        ForEach(appleVoices) { Text($0.name).tag($0.id) }
                        if !ttsAppleVoice.isEmpty, !appleVoices.contains(where: { $0.id == ttsAppleVoice }) {
                            Text(ttsAppleVoice).tag(ttsAppleVoice)
                        }
                    }
                    Text("Speaks replies on-device — no server needed.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    TextField("Kokoro server URL", text: $ttsServerURL)
                        .autocorrectionDisabled()
                    HStack(spacing: 8) {
                        Button("Test") { Task { await testTTSServer() } }
                            .disabled(ttsTesting || ttsServerURL.isEmpty)
                        if ttsTesting { ProgressView().controlSize(.small) }
                        if let status = ttsTestStatus {
                            Label(status, systemImage: ttsTestOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(ttsTestOK ? .green : .red)
                                .font(.caption).lineLimit(2)
                        }
                    }
                    Picker("Voice", selection: $ttsVoice) {
                        Text("None").tag("")
                        ForEach(ttsVoices) { Text($0.name).tag($0.id) }
                        if !ttsVoice.isEmpty, !ttsVoices.contains(where: { $0.id == ttsVoice }) {
                            Text(ttsVoice).tag(ttsVoice)
                        }
                    }
                    Text("A local Kokoro-FastAPI server (OpenAI-compatible). Run Test to load voices.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Stepper(value: $ttsSpeed, in: 0.5...2.0, step: 0.1) {
                    Text("Speed: \(ttsSpeed, specifier: "%.1f")×")
                }
                Text("Enable speech per chat in Session Settings (with an optional auto-speak).")
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Speech-to-Text") {
                Toggle("Enable speech-to-text", isOn: $sttFeatureEnabled)
                if sttFeatureEnabled {
                Toggle("Auto-send after a pause", isOn: $dictationAutoSend)
                if dictationAutoSend {
                    Stepper(value: $dictationPauseSeconds, in: 0.5...5.0, step: 0.5) {
                        Text("Pause: \(dictationPauseSeconds, specifier: "%.1f")s")
                    }
                }
                Toggle("Reduce background noise & echo", isOn: $voiceProcessing)
                Toggle("Conversation mode (always-on, hands-free)", isOn: $conversationMode)
                Text("Tap the mic in the composer to dictate. Recognition runs on-device when supported. With auto-send off, dictation fills the message box and you send it yourself.")
                    .font(.caption).foregroundStyle(.secondary)
                if conversationMode {
                    Text("Adds an ear button to the composer: the mic stays on, sends each utterance after a pause, and listens again after the reply (it pauses while a spoken reply plays).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Requires Dictation to be turned on in System Settings ▸ Keyboard.")
                    .font(.caption).foregroundStyle(.secondary)
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
        #if os(macOS)
        .frame(width: 480, height: 640)
        #endif
        .task {
            appleVoices = AppleSpeech.voices()
            await loadModels()
        }
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

    /// The web-search settings assembled from the @AppStorage keys, including which providers
    /// are enabled for meta-search.
    private var webSearchConfig: WebSearchConfig {
        WebSearchConfig(searxngURL: searxngURL,
                        braveAPIKey: braveAPIKey,
                        tavilyAPIKey: tavilyAPIKey,
                        exaAPIKey: exaAPIKey,
                        linkupAPIKey: linkupAPIKey,
                        tinyfishAPIKey: tinyfishAPIKey,
                        marginaliaAPIKey: marginaliaAPIKey,
                        enabledProviders: WebSearchSettings.enabledProviders(disabledCSV: metaDisabledProviders),
                        metaMode: WebSearch.MetaSearchMode(rawValue: metaMode) ?? .comprehensive)
    }

    /// Whether a web-search provider has the key/URL it needs (from the @AppStorage keys).
    private func providerReady(_ provider: WebSearch.ProviderKind) -> Bool {
        WebSearch.isReady(provider, config: webSearchConfig)
    }

    /// The chat/LLM backends the user can connect. Image generation is an optional
    /// Feature configured in its own section.
    private var configurableBackends: [BackendKind] {
        BackendKind.allCases.filter { $0.profile.isChatBackend }
    }

    private var defaultBackendKind: BackendKind {
        BackendKind(rawValue: defaultBackend) ?? .ollama
    }

    /// Which backend the Backends section is configuring. Backed by @AppStorage so it
    /// persists across Settings opens; when never chosen it follows the default backend
    /// new chats use, so the section opens showing the backend you actually connected.
    private var configuringBackend: BackendKind {
        BackendKind(rawValue: configuringBackendRaw)
            ?? BackendKind(rawValue: defaultBackend)
            ?? .ollama
    }

    /// Caption under New chats, tailored to the chosen preset or default backend.
    private var newChatsNote: String {
        if let preset = SessionPresetLibrary.preset(id: defaultPresetID, in: sessionPresetsJSON) {
            return "New chats start from the \u{201c}\(preset.name)\u{201d} preset. Change anything per chat in Session Settings."
        }
        switch defaultBackendKind {
        case .llamaServer:
            return "New chats use the llama.cpp server (its single model and context window come from the server). Change anything per chat, or save a chat's setup as a preset to reuse it."
        case .appleIntelligence:
            return "New chats use Apple Intelligence (on-device, one model). Change anything per chat, or save a chat's setup as a preset to reuse it."
        default:
            return "New chats begin with these values. Change anything per chat, or save a chat's setup as a preset (from Session Settings) to reuse it."
        }
    }

    /// Saved session presets (decoded from the app-wide library).
    private var sessionPresets: [SessionPreset] {
        SessionPresetLibrary.decode(sessionPresetsJSON)
    }

    private func deletePreset(_ preset: SessionPreset) {
        var presets = SessionPresetLibrary.decode(sessionPresetsJSON)
        presets.removeAll { $0.id == preset.id }
        sessionPresetsJSON = SessionPresetLibrary.encode(presets)
        if defaultPresetID == preset.id { defaultPresetID = "" }
    }

    private func backendURLBinding() -> Binding<String> {
        switch configuringBackend {
        case .llamaServer: return $llamaServerURL
        default: return $serverURL
        }
    }

    private var backendURLPlaceholder: String {
        configuringBackend == .llamaServer ? "http://localhost:8080" : "http://localhost:11434"
    }

    private var backendBlurb: String {
        switch configuringBackend {
        case .ollama:
            return "A local or networked Ollama server. Streams chat, lists and manages models, and provides embeddings for retrieval over attachments."
        case .llamaServer:
            return "A llama.cpp llama-server (OpenAI-compatible API). Serves one model at a context window fixed at launch."
        case .appleIntelligence:
            return "Apple's on-device model. Nothing to configure — it runs entirely on this Mac when Apple Intelligence is enabled in System Settings."
        case .imageGeneration:
            return ""
        }
    }

    /// A small "i" info affordance: a hover tooltip on macOS, a tap-to-show popover on iOS.
    private func infoButton(_ help: String) -> some View {
        InfoButton(text: help)
    }

    /// One "Backends" area: pick a backend, configure its connection, and test it. Only
    /// the controls that backend needs appear — driven by its capability profile.
    private var backendsSection: some View {
        let profile = configuringBackend.profile
        return Section("Backends") {
            Picker("Backend", selection: Binding(
                get: { configuringBackend.rawValue },
                set: { configuringBackendRaw = $0 }
            )) {
                ForEach(configurableBackends) { kind in
                    Text(kind.label).tag(kind.rawValue)
                }
            }
            if profile.needsServerURL {
                LabeledContent("Server") {
                    HStack(spacing: 6) {
                        TextField("", text: backendURLBinding(), prompt: Text(backendURLPlaceholder))
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                        infoButton(backendBlurb)
                    }
                }
                HStack(spacing: 8) {
                    Button("Test Connection") { Task { await runBackendTest() } }
                        .disabled(backendTesting || backendURLBinding().wrappedValue.isEmpty)
                    if backendTesting { ProgressView().controlSize(.small) }
                    if let backendTestStatus {
                        Label(backendTestStatus, systemImage: backendTestOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(backendTestOK ? Color.green : Color.red)
                            .font(.caption).lineLimit(2)
                    }
                }
            } else if profile.isOnDevice {
                Label(AppleIntelligence.statusMessage,
                      systemImage: AppleIntelligence.isAvailable ? "checkmark.seal" : "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                if !backendBlurb.isEmpty {
                    Text(backendBlurb).font(.caption).foregroundStyle(.secondary)
                }
            }
            if profile.supportsModelManagement {
                Button { showingModelManager = true } label: {
                    Label("Manage Models…", systemImage: "shippingbox")
                }
            }
            if profile.contextWindowAdjustable {
                Toggle("Right-size context to each request", isOn: $rightSizeContext)
                Text("Sends only as much context window as a request needs, capped to the model's real limit. Uses less memory and loads faster; turn off to always send the full size.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if profile.supportsKeepAlive {
                Picker("Keep model loaded", selection: $keepAliveMinutes) {
                    Text("Server default (5 min)").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("Always loaded").tag(-1)
                }
                Text("How long Ollama keeps the model in memory after a reply. Longer keeps it warm; holds VRAM.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Tests the selected backend's connection: Ollama via its version endpoint,
    /// llama.cpp by listing its loaded model. Apple needs no connection.
    private func runBackendTest() async {
        backendTesting = true
        backendTestStatus = nil
        defer { backendTesting = false }
        switch configuringBackend {
        case .ollama:
            switch await ServerProbe.checkVersion(baseURL: serverURL) {
            case .success(let version):
                backendTestOK = true
                backendTestStatus = "Connected to Ollama \(version)."
            case .failure(let reason):
                backendTestOK = false
                backendTestStatus = reason
            }
        case .llamaServer:
            guard let client = LlamaServerClient(baseURLString: llamaServerURL) else {
                backendTestOK = false
                backendTestStatus = "That doesn't look like a valid URL."
                return
            }
            do {
                let models = try await client.models()
                backendTestOK = true
                backendTestStatus = models.first.map { "Connected · \($0.name)" } ?? "Connected."
            } catch {
                backendTestOK = false
                backendTestStatus = error.localizedDescription
            }
        default:
            break
        }
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

    /// ComfyUI workflow-template management: import an API-format workflow (auto-bound to txt2img
    /// parameters) and manage the library. Shown only when the ComfyUI backend is selected.
    private var comfyTemplatesView: some View {
        let templates = ComfyTemplateLibrary.decode(comfyTemplatesJSON)
        return Group {
            Divider()
            Text("Workflow Templates").font(.subheadline.weight(.semibold))
            Text("Import a workflow exported from ComfyUI in API format (Dev mode → Save API). Llamatron detects the txt2img parameters so a chat can drive it like any image backend.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(templates) { template in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(template.name)
                        Text("\(template.parameters.count) parameters detected")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) { deleteComfyTemplate(template) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this template")
                }
            }
            HStack(spacing: 8) {
                Button("Import Workflow…") { importComfyTemplate() }
                if let comfyImportStatus {
                    Text(comfyImportStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    /// Opens an API-format workflow file, auto-binds it to a template, and adds it to the library.
    private func importComfyTemplate() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a ComfyUI workflow saved in API format."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        applyComfyWorkflow(from: url)
        #else
        PlatformOpen.pick([.json]) { url in
            guard let url else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            applyComfyWorkflow(from: url)
        }
        #endif
    }

    /// Reads a ComfyUI workflow file, auto-binds it to a template, and adds it to the library.
    private func applyComfyWorkflow(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let name = url.deletingPathExtension().lastPathComponent
            guard let template = ComfyWorkflowTemplate.textToImage(name: name, workflowJSON: data) else {
                comfyImportStatus = "“\(name)” isn't a text-to-image workflow (no prompt/model/seed detected). Make sure it's saved in API format."
                return
            }
            var templates = ComfyTemplateLibrary.decode(comfyTemplatesJSON)
            templates.append(template)
            comfyTemplatesJSON = ComfyTemplateLibrary.encode(templates)
            comfyImportStatus = "Imported “\(name)” — \(template.parameters.count) parameters detected."
        } catch {
            comfyImportStatus = "Couldn't read that file."
        }
    }

    /// Removes a template from the library.
    private func deleteComfyTemplate(_ template: ComfyWorkflowTemplate) {
        var templates = ComfyTemplateLibrary.decode(comfyTemplatesJSON)
        templates.removeAll { $0.id == template.id }
        comfyTemplatesJSON = ComfyTemplateLibrary.encode(templates)
    }

    private func testTTSServer() async {
        ttsTesting = true
        ttsTestStatus = nil
        let provider = TTS.serverProvider(baseURLString: ttsServerURL)
        do {
            let voices = try await provider.listVoices().sorted { $0.name < $1.name }
            ttsVoices = voices
            ttsTestOK = !voices.isEmpty
            ttsTestStatus = voices.isEmpty
                ? "Connected, but found no voices."
                : "Found \(voices.count) voice\(voices.count == 1 ? "" : "s")."
            if ttsVoice.isEmpty, let first = voices.first { ttsVoice = first.id }
        } catch {
            ttsTestOK = false
            ttsTestStatus = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach the server."
        }
        ttsTesting = false
    }
}
