import SwiftUI
import LlamaEngine
import AppKit
import UniformTypeIdentifiers

/// App-wide settings (Cmd-,). Server address plus defaults applied to new sessions.
struct SettingsView: View {
    @AppStorage(SettingsKey.serverURL) private var serverURL = SettingsDefault.serverURL
    @AppStorage(SettingsKey.defaultContextSize) private var defaultContextSize = SettingsDefault.contextSize
    @AppStorage(SettingsKey.defaultModel) private var defaultModel = ""
    @AppStorage(SettingsKey.requestTimeout) private var requestTimeout = SettingsDefault.timeout
    @AppStorage(SettingsKey.embeddingModel) private var embeddingModel = SettingsDefault.embeddingModel
    @AppStorage(SettingsKey.diagramGuidance) private var diagramGuidance = false
    @AppStorage(SettingsKey.rightSizeContext) private var rightSizeContext = SettingsDefault.rightSizeContext
    @AppStorage(SettingsKey.keepAliveMinutes) private var keepAliveMinutes = SettingsDefault.keepAliveMinutes

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

    @AppStorage(SettingsKey.comfyTemplates) private var comfyTemplatesJSON = "[]"
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
                Toggle("Right-size context to each request", isOn: $rightSizeContext)
                Text("Sends only as much context window as a request needs (up to the size above), capped to the model's real limit. Uses less memory and loads faster on modest hardware; turn off to always send the full size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Keep model loaded", selection: $keepAliveMinutes) {
                    Text("Server default (5 min)").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("Always loaded").tag(-1)
                }
                Text("How long Ollama keeps the model in memory after a reply. Longer keeps it warm for faster follow-ups but holds VRAM.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    if imageBackendKind == ImageBackendKind.comfyUI.rawValue {
                        comfyTemplatesView
                    }
                }
            }
            Section("Text-to-Speech") {
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
            Section("Speech-to-Text") {
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
            Section("Rendering") {
                Toggle("Guide models to render diagrams inline", isOn: $diagramGuidance)
                Text("Adds a short system instruction so models emit valid Mermaid diagrams (quoted labels) and skip “paste into an online editor” notes. Diagrams render inline in the chat. Appears in the request payload, visible in the turn inspector.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
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
                        Text("\(template.kind.label) · \(template.parameters.count) parameters detected")
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
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a ComfyUI workflow saved in API format."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let name = url.deletingPathExtension().lastPathComponent
            let template = ComfyWorkflowTemplate.autobound(name: name, workflowJSON: data)
            guard !template.parameters.isEmpty else {
                comfyImportStatus = "No parameters found in “\(name)”. Make sure it's saved in API format, not the default workflow format."
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
