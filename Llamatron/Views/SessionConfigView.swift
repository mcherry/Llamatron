import SwiftUI
import LlamaEngineStore
import LlamaEngine

/// Per-session configuration: which model to use, the context window, and the
/// system prompt. Models are loaded live from the server (embedding-only models
/// filtered out) with a refresh button. Edits are written straight onto the
/// `ChatSession` and affect subsequent requests only.
import SwiftUI
import SwiftData

/// Per-session configuration: which model to use, the context window, and the
/// system prompt. Models are loaded live from the server (embedding-only models
/// filtered out) with a refresh button. Edits are written straight onto the
/// `ChatSession` and affect subsequent requests only.
struct SessionConfigView: View {
    @Bindable var session: ChatSession
    let serverURL: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PromptPreset.name) private var presets: [PromptPreset]
    @State private var models: [OllamaModel] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var customContext = ""
    @State private var appleStatus = AppleIntelligence.status
    @State private var showingSavePreset = false
    @State private var newPresetName = ""
    /// The session model's trained context length (`/api/show`), for the cap warning.
    @State private var modelMaxContext: Int?
    /// Whether the selected Ollama model reports the "thinking" capability (`/api/show`).
    /// `nil` = unknown (llama.cpp or not reported) → keep the reasoning control visible;
    /// `false` = the model can't reason → hide it.
    @State private var modelSupportsThinking: Bool?

    // Local text mirrors of the optional numeric parameters, so typing ("0.") doesn't
    // get reformatted mid-edit. Committed to the session on change.
    @State private var tempText = ""
    @State private var topPText = ""
    @State private var topKText = ""
    @State private var repeatText = ""
    @State private var seedText = ""
    @State private var stopText = ""
    @State private var maxTokensText = ""

    @AppStorage(SettingsKey.sessionPresets) private var sessionPresetsJSON = "[]"
    @AppStorage("session.showAdvanced") private var showAdvanced = false
    @State private var showingSaveSessionPreset = false
    @State private var newSessionPresetName = ""
    @AppStorage(SettingsKey.imageGenEnabled) private var imageGenEnabled = false
    @AppStorage(SettingsKey.llamaServerURL) private var llamaServerURL = SettingsDefault.llamaServerURL
    @AppStorage(SettingsKey.ttsFeatureEnabled) private var ttsFeatureEnabled = SettingsDefault.ttsFeatureEnabled
    @AppStorage(SettingsKey.imageServerURL) private var imageServerURL = SettingsDefault.imageServerURL
    @AppStorage(SettingsKey.imageBackendKind) private var imageBackendKind = ImageBackendKind.easyDiffusion.rawValue
    @AppStorage(SettingsKey.comfyTemplates) private var comfyTemplatesJSON = "[]"
    @State private var imageModels: [ImageModel] = []
    @State private var imageVAEs: [ImageModel] = []
    @State private var imageTesting = false
    @State private var imageLoadError: String?
    @State private var comfyIssues: [ComfyValidationIssue] = []
    @State private var showingServerImport = false

    /// Shared width for the generation parameter entry fields.
    private let fieldWidth: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Session Settings").font(.headline)
                    Text("Applies to this chat only").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                presetSection
                backendSection
                if profile.listsModels && profile.isChatBackend {
                    if profile.modelSelectable {
                        modelSection
                    } else {
                        fixedModelSection
                    }
                }
                if profile.isChatBackend {
                    systemPromptSection
                }
                if profile.producesImages {
                    imageSection
                }

                Section {
                    Toggle(isOn: $showAdvanced) {
                        Label("Advanced settings", systemImage: "slider.horizontal.3")
                    }
                } footer: {
                    Text("Generation, context window, history, retrieval\(profile.supportsVision ? ", vision" : "")\(ttsFeatureEnabled && profile.isChatBackend ? ", and speech" : "").")
                }

                if showAdvanced {
                    if profile.supportsVision {
                        visionSection
                    }
                    if profile.contextWindowAdjustable {
                        contextSection
                    } else if profile.isChatBackend && !profile.isOnDevice {
                        fixedContextSection
                    }
                    if profile.supportsSampling {
                        generationSection
                    }
                    if profile.isOnDevice {
                        appleGenerationSection
                    }
                    if profile.isChatBackend {
                        historySection
                        contextStrategySection
                        if ttsFeatureEnabled {
                            speechSection
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 470, height: 620)
        #endif
        .task { await loadModels() }
        .task(id: session.backend) {
            await loadModels()
            if session.backend == .imageGeneration {
                await loadImageModels()
                await validateComfyTemplate()
            }
        }
        .onChange(of: session.comfyTemplateID) {
            applyComfyTemplateDefaults()
            Task { await validateComfyTemplate() }
        }
        .sheet(isPresented: $showingServerImport) {
            ComfyServerImportSheet(serverURL: imageServerURL) { importServerTemplate($0) }
        }
        .task(id: session.modelName) { await loadModelContext() }
        .onAppear(perform: loadParameterFields)
    }

    /// The capability profile for the session's current backend — drives which
    /// settings sections appear, so the UI never shows a control the backend can't use.
    private var profile: BackendProfile { session.backend.profile }

    // MARK: - Presets

    /// Saved session presets (decoded from the app-wide library).
    private var sessionPresets: [SessionPreset] {
        SessionPresetLibrary.decode(sessionPresetsJSON)
    }

    /// A sensible starting name when saving a preset.
    private var suggestedPresetName: String {
        session.modelName.isEmpty ? session.backend.label : session.modelName
    }

    private var presetSection: some View {
        Section {
            HStack {
                Menu {
                    if sessionPresets.isEmpty {
                        Text("No saved presets")
                    } else {
                        ForEach(sessionPresets) { preset in
                            Button(preset.name) { applyPreset(preset) }
                        }
                    }
                } label: {
                    Label("Apply Preset", systemImage: "square.stack.3d.up")
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                .fixedSize()
                #endif

                Spacer()

                Button {
                    newSessionPresetName = suggestedPresetName
                    showingSaveSessionPreset = true
                } label: {
                    Label("Save as Preset", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        } header: {
            Text("Preset")
        } footer: {
            Text("Save this chat's setup to reuse it, or apply a saved one. Choose the default for new chats in Settings \u{203a} New chats.")
        }
        .alert("Save Preset", isPresented: $showingSaveSessionPreset) {
            TextField("Name", text: $newSessionPresetName)
            Button("Save", action: saveSessionPreset)
                .disabled(newSessionPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves this chat's backend, model, system prompt, and generation settings as a reusable preset.")
        }
    }

    private func applyPreset(_ preset: SessionPreset) {
        session.apply(preset.config)
        loadParameterFields()
    }

    private func saveSessionPreset() {
        let name = newSessionPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var presets = SessionPresetLibrary.decode(sessionPresetsJSON)
        presets.append(SessionPreset(name: name, config: session.configSnapshot()))
        sessionPresetsJSON = SessionPresetLibrary.encode(presets)
        newSessionPresetName = ""
    }

    private var backendSection: some View {
        Section("Backend") {
            Picker("Engine", selection: $session.backend) {
                Text(BackendKind.ollama.label).tag(BackendKind.ollama)
                Text(BackendKind.llamaServer.label).tag(BackendKind.llamaServer)
                // Offer Apple Intelligence only when the system reports it available,
                // but keep an already-chosen value visible so it isn't silently reset.
                if appleStatus == .available || session.backend == .appleIntelligence {
                    Text(BackendKind.appleIntelligence.label).tag(BackendKind.appleIntelligence)
                }
                if imageGenEnabled || session.backend == .imageGeneration {
                    Text(BackendKind.imageGeneration.label).tag(BackendKind.imageGeneration)
                }
            }

            if session.backend == .llamaServer {
                Text("Uses the llama.cpp server configured in Settings (OpenAI-compatible API).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            switch appleStatus {
            case .available:
                Label("Apple Intelligence is available on this Mac.", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            default:
                Label(AppleIntelligence.statusMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if session.backend == .appleIntelligence {
                Text("Runs entirely on-device. Attached-file retrieval and embeddings still use the Ollama server; without one, large files fall back to truncation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelSection: some View {
        Section("Model") {
            HStack {
                Picker("Model", selection: $session.modelName) {
                    Text("Select a model…").tag("")
                    ForEach(models) { model in
                        Text(model.name).tag(model.name)
                    }
                    // Keep a previously chosen model selectable even if the server
                    // no longer lists it.
                    if !session.modelName.isEmpty,
                       !models.contains(where: { $0.name == session.modelName }) {
                        Text(session.modelName).tag(session.modelName)
                    }
                }
                Button {
                    Task { await loadModels() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loading)
                .help("Refresh model list")
            }

            if loading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading models…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Read-only model display for server backends that serve a single fixed model
    /// (llama.cpp): the app auto-selects the loaded model rather than offering a picker.
    private var fixedModelSection: some View {
        Section("Model") {
            if !session.modelName.isEmpty {
                LabeledContent("Model", value: session.modelName)
            } else if loading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading model…").font(.caption).foregroundStyle(.secondary)
                }
            } else if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            } else {
                Text("Connect to the server in Settings to load its model.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("The llama.cpp server serves one model, loaded at launch — there's nothing to pick here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var visionSection: some View {
        Section("Vision") {
            Picker("Vision model", selection: $session.visionModel) {
                Text("None").tag("")
                ForEach(visionModels) { model in
                    Text(model.name).tag(model.name)
                }
                if !session.visionModel.isEmpty,
                   !visionModels.contains(where: { $0.name == session.visionModel }) {
                    Text(session.visionModel).tag(session.visionModel)
                }
            }
            Text(visionHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var contextSection: some View {
        Section("Context Size") {
            Picker("Preset", selection: $session.contextSize) {
                ForEach(ContextSize.presets, id: \.self) { size in
                    Text(ContextSize.label(size)).tag(size)
                }
                if !ContextSize.presets.contains(session.contextSize) {
                    Text("\(session.contextSize) (custom)").tag(session.contextSize)
                }
            }
            HStack {
                TextField("Custom tokens", text: $customContext)
                    .onSubmit(applyCustomContext)
                Button("Set", action: applyCustomContext)
                    .disabled(Int(customContext.filter(\.isNumber)) == nil)
            }
            if let modelMaxContext {
                if session.contextSize > modelMaxContext {
                    Label("Above this model's limit of \(ContextSize.label(modelMaxContext)); the server will cap it. Larger values won't add usable context.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("This model supports up to \(ContextSize.label(modelMaxContext)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Larger context uses more memory. Values above a model's limit are clamped or rejected by the server.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Read-only context-window display for server backends whose window is fixed at
    /// launch (llama.cpp `-c`), which the app discovers rather than lets the user set.
    private var fixedContextSection: some View {
        Section("Context Window") {
            if let modelMaxContext {
                LabeledContent("Window", value: ContextSize.label(modelMaxContext))
            }
            Text("Fixed by the server at launch (llama.cpp `-c`). The app fits context and history to this window; you don't set it here.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var generationSection: some View {
        Section("Generation") {
            if profile.supportsReasoning && modelSupportsThinking != false {
                Picker("Reasoning", selection: $session.reasoningMode) {
                    ForEach(ReasoningMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text(reasoningHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            parameterField("Temperature", text: $tempText,
                           help: "Higher values make output more random and creative; lower values make it more focused and predictable. Blank uses the server default.") {
                session.temperature = parseDouble(tempText)
            }
            parameterField("Top P", text: $topPText,
                           help: "Nucleus sampling: the model only considers the most likely tokens whose probabilities add up to P. Lower is more focused. Blank uses the server default.") {
                session.topP = parseDouble(topPText)
            }
            parameterField("Top K", text: $topKText,
                           help: "The model samples only from the K most likely tokens. Lower is more focused. Blank uses the server default.") {
                session.topK = parseInt(topKText)
            }
            parameterField("Repeat penalty", text: $repeatText,
                           help: "Penalizes tokens that have already appeared to reduce repetition. Above 1 discourages repeats. Blank uses the server default.") {
                session.repeatPenalty = parseDouble(repeatText)
            }

            parameterField("Max response tokens", text: $maxTokensText,
                           help: "Caps how many tokens the model may generate (Ollama num_predict), a safety net against runaway replies. For thinking models this counts reasoning + answer. Blank uses the server default (unlimited within the window).") {
                session.maxResponseTokens = parseInt(maxTokensText)
            }

            seedRow

            LabeledContent("Stop sequences") {
                HStack(spacing: 6) {
                    TextField("", text: $stopText)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1)
                        .frame(width: fieldWidth)
                        .onChange(of: stopText) {
                            session.stopSequences = stopText
                                .split(whereSeparator: { $0 == "," || $0 == "\n" })
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                    infoButton("Generation stops as soon as the model produces any of these strings (e.g. \"User:\"). Separate multiple with commas.")
                }
            }

            Button("Reset to Defaults", action: clearGenerationParameters)
                .disabled(session.generationParameters.isEmpty && session.maxResponseTokens == nil)
        }
    }

    /// Backend-aware explanation of the Reasoning control so it's clear when it applies.
    private var reasoningHelpText: String {
        switch session.backend {
        case .llamaServer:
            return "For reasoning models (e.g. gpt-oss), the server streams the model's thinking into a collapsible section. Automatic uses the model's default; On asks for more reasoning, Off minimizes it."
        default:
            return "This model can think, and its reasoning shows in a collapsible section. Automatic uses the model's default; On asks for more, Off minimizes it. (This control only appears for models that support reasoning.)"
        }
    }

    /// Apple Intelligence generation controls. Apple exposes far fewer knobs than
    /// Ollama: temperature, a response-token cap, and a single sampling-mode choice
    /// (which bundles top-k / top-p / greedy), with a seed for the random modes.
    private var appleGenerationSection: some View {
        Section("Generation") {
            parameterField("Temperature", text: $tempText,
                           help: "Higher values make output more random and creative; lower values make it more focused and predictable. Blank uses Apple's default.") {
                session.temperature = parseDouble(tempText)
            }
            parameterField("Max response tokens", text: $maxTokensText,
                           help: "Caps how many tokens the model may generate in its reply. Blank uses Apple's default.") {
                session.maxResponseTokens = parseInt(maxTokensText)
            }
            Picker("Sampling", selection: $session.appleSamplingMode) {
                ForEach(AppleSamplingMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            if session.appleSamplingMode == .topK {
                parameterField("Top-K", text: $topKText,
                               help: "The model samples only from the K most likely tokens. Lower is more focused.") {
                    session.topK = parseInt(topKText)
                }
            }
            if session.appleSamplingMode == .topP {
                parameterField("Top-P", text: $topPText,
                               help: "Nucleus sampling: the model only considers the most likely tokens whose probabilities add up to P. Lower is more focused.") {
                    session.topP = parseDouble(topPText)
                }
            }
            if session.appleSamplingMode.usesSeed {
                seedRow
            }
            Text("Greedy is deterministic. Top-K / Top-P with a fixed seed give reproducible output. Blank fields use Apple's defaults.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Reset to Defaults", action: clearAppleParameters)
                .disabled(session.appleOptions.isEmpty)
        }
    }

    /// Shared seed field + randomize button (used by both backends' sections).
    private var seedRow: some View {
        LabeledContent("Seed") {
            HStack(spacing: 6) {
                Button {
                    let value = Int.random(in: 0...Int(UInt32.max))
                    seedText = String(value)
                    session.seed = value
                } label: {
                    Image(systemName: "die.face.5")
                }
                .buttonStyle(.borderless)
                .help("Set a random seed")
                TextField("", text: $seedText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: fieldWidth)
                    .onChange(of: seedText) { session.seed = parseInt(seedText) }
                infoButton("Fixes the random seed so identical requests reproduce the same output. Blank uses a new random seed each time.")
            }
        }
    }

    /// A numeric text field row with a trailing info icon, committing on change.
    private func parameterField(_ title: String,
                                text: Binding<String>,
                                help: String,
                                commit: @escaping () -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: fieldWidth)
                    .onChange(of: text.wrappedValue) { commit() }
                infoButton(help)
            }
        }
    }

    /// A small "i" info affordance: a hover tooltip on macOS, a tap-to-show popover on iOS.
    private func infoButton(_ help: String) -> some View {
        InfoButton(text: help)
    }

    private var imageSection: some View {
        Section("Image Generation") {
            if !imageGenEnabled {
                Label("Turn on image generation in Settings, then pick a model here.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                if isComfyUI {
                    comfyTemplatePicker
                }
                HStack {
                    Picker("Image model", selection: $session.imageModel) {
                        Text("Select a model…").tag("")
                        ForEach(imageModels) { Text($0.name).tag($0.id) }
                        if !session.imageModel.isEmpty, !imageModels.contains(where: { $0.id == session.imageModel }) {
                            Text(session.imageModel).tag(session.imageModel)
                        }
                    }
                    Button {
                        Task { await loadImageModels() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(imageTesting)
                    .help("Load models from the image server")
                }
                if imageTesting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading models…").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let imageLoadError {
                    Label(imageLoadError, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                }
                Stepper("Steps: \(session.imageSteps)", value: $session.imageSteps, in: 1...150)
                Stepper("Size: \(session.imageSize)px", value: $session.imageSize, in: 256...2048, step: 64)
                Stepper(value: $session.imageCFG, in: 1...20, step: 0.5) {
                    Text("Guidance (CFG): \(session.imageCFG, specifier: "%.1f")")
                }
                if !isComfyUI {
                    Picker("Sampler", selection: $session.imageSampler) {
                        ForEach(ImageSampler.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("VAE", selection: $session.imageVAE) {
                        Text("Model default").tag("")
                        ForEach(imageVAEs) { Text($0.name).tag($0.id) }
                        if !session.imageVAE.isEmpty, !imageVAEs.contains(where: { $0.id == session.imageVAE }) {
                            Text(session.imageVAE).tag(session.imageVAE)
                        }
                    }
                    Picker("Upscale", selection: $session.imageUpscaler) {
                        ForEach(ImageUpscaler.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    if session.imageUpscaler == ImageUpscaler.latent.rawValue {
                        Stepper("Upscaler steps: \(session.imageLatentUpscalerSteps)",
                                value: $session.imageLatentUpscalerSteps, in: 1...50)
                    } else if !session.imageUpscaler.isEmpty {
                        Picker("Upscale by", selection: $session.imageUpscaleAmount) {
                            Text("2×").tag(2)
                            Text("4×").tag(4)
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("Face correction", selection: $session.imageFaceCorrection) {
                        ForEach(FaceCorrection.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Toggle("CLIP skip", isOn: $session.imageClipSkip)
                }
                TextField("Negative prompt (optional)", text: $session.imageNegativePrompt, axis: .vertical)
                    .lineLimit(1...3)
                Text("Prompts in this chat are sent to the image server; the rendered image appears in the reply.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Loads the image server's models into the per-chat picker, defaulting the chosen
    /// model to the first one when none is set yet.
    private func loadImageModels() async {
        imageTesting = true
        imageLoadError = nil
        let kind = ImageBackendKind(rawValue: imageBackendKind) ?? .easyDiffusion
        let provider = kind.makeProvider(baseURLString: imageServerURL)
        do {
            let fetched = try await provider.listModels().sorted { $0.name < $1.name }
            imageModels = fetched
            imageVAEs = (try? await provider.listVAEs())?.sorted { $0.name < $1.name } ?? []
            if session.imageModel.isEmpty, let first = fetched.first { session.imageModel = first.id }
            if fetched.isEmpty { imageLoadError = "Connected, but found no image models." }
        } catch {
            imageLoadError = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach the image server."
        }
        imageTesting = false
    }

    private var isComfyUI: Bool { ImageBackendKind(rawValue: imageBackendKind) == .comfyUI }
    private var comfyTemplates: [ComfyWorkflowTemplate] { ComfyTemplateLibrary.decode(comfyTemplatesJSON) }
    private var selectedComfyTemplate: ComfyWorkflowTemplate? {
        ComfyTemplateLibrary.template(id: session.comfyTemplateID, in: comfyTemplatesJSON)
    }

    /// ComfyUI workflow picker plus a pre-flight warning when the chosen template needs models or
    /// custom nodes the server doesn't have.
    @ViewBuilder private var comfyTemplatePicker: some View {
        Picker("Workflow", selection: $session.comfyTemplateID) {
            Text("Select a workflow…").tag("")
            ForEach(comfyTemplates) { Text($0.name).tag($0.id.uuidString) }
        }
        Button {
            showingServerImport = true
        } label: {
            Label("Add from server…", systemImage: "square.and.arrow.down.on.square")
        }
        .disabled(imageServerURL.isEmpty)
        .help("Pull a recent, saved, or built-in workflow straight from the ComfyUI server")
        if comfyTemplates.isEmpty {
            Label("Add a workflow from the server, or import one in Settings → Image Generation.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(comfyIssues.filter(\.isBlocking), id: \.self) { issue in
            Label(issue.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    /// Seeds this chat's controls from the template's authored defaults, so a turbo model's real
    /// steps/cfg/size/model apply instead of the app's Easy-Diffusion defaults.
    private func applyComfyTemplateDefaults() {
        guard let template = selectedComfyTemplate else { return }
        if let steps = template.defaultInt(.steps) { session.imageSteps = steps }
        if let cfg = template.defaultDouble(.cfg) { session.imageCFG = cfg }
        if let width = template.defaultInt(.width) { session.imageSize = width }
        if let model = template.defaultString(.model) { session.imageModel = model }
    }

    /// Checks the chosen template against the server (missing models / custom nodes) for a warning.
    private func validateComfyTemplate() async {
        comfyIssues = []
        guard isComfyUI, let template = selectedComfyTemplate, !imageServerURL.isEmpty else { return }
        let provider = ComfyUIProvider(baseURLString: imageServerURL, template: template)
        comfyIssues = (try? await provider.validate()) ?? []
    }

    /// Imports a workflow pulled from the server: adds it to the library, selects it for this chat,
    /// and seeds the controls from its authored defaults.
    private func importServerTemplate(_ template: ComfyWorkflowTemplate) {
        var templates = ComfyTemplateLibrary.decode(comfyTemplatesJSON)
        templates.append(template)
        comfyTemplatesJSON = ComfyTemplateLibrary.encode(templates)
        session.comfyTemplateID = template.id.uuidString
        applyComfyTemplateDefaults()
        Task { await validateComfyTemplate() }
    }

    private var speechSection: some View {
        Section("Speech") {
            Toggle("Read replies aloud", isOn: $session.ttsEnabled)
            if session.ttsEnabled {
                Picker("Engine", selection: $session.ttsEngine) {
                    ForEach(TTSEngine.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Speak automatically when a reply finishes", isOn: $session.ttsAutoSpeak)
                Text("Voices and speed are set in Settings → Text-to-Speech.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var historySection: some View {
        Section("Conversation History") {
            Picker("When the window fills", selection: $session.historyMode) {
                ForEach(HistoryMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text(session.historyMode.help)
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.historyMode.needsServer && session.backend == .appleIntelligence {
                Label("Without a reachable Ollama server, this falls back to truncation.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Models are stateless, so the whole conversation is re-sent each turn. Short chats always send in full; these modes only engage once the history would overflow the window.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var contextStrategySection: some View {
        Section("Attached Files") {
            Picker("Strategy", selection: $session.contextMode) {
                ForEach(ContextMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text(session.contextMode.help)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Automatic picks by size: small files are sent whole, larger files are retrieved or summarized, with truncation as a last resort. Re-run a chat with a different setting to try another approach.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if profile.supportsRetrieval {
                Text("Retrieval finds the most relevant excerpts of large attachments using on-device embeddings (Apple's Natural Language framework) — no server or model to set up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var systemPromptSection: some View {
        Section("System Prompt") {
            HStack {
                Menu {
                    if presets.isEmpty {
                        Text("No saved prompts")
                    } else {
                        ForEach(presets) { preset in
                            Button(preset.name) { session.systemPrompt = preset.content }
                        }
                        Divider()
                        Menu("Delete") {
                            ForEach(presets) { preset in
                                Button(preset.name, role: .destructive) {
                                    modelContext.delete(preset)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Library", systemImage: "books.vertical")
                }
                #if os(macOS)
                .menuStyle(.borderlessButton)
                .fixedSize()
                #endif

                Spacer()

                Button {
                    newPresetName = ""
                    showingSavePreset = true
                } label: {
                    Label("Save as Preset", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(session.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextEditor(text: $session.systemPrompt)
                .font(.body)
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
                .frame(minHeight: 100)
            HStack {
                Spacer()
                Text(systemPromptCostLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text("Sent as the leading system message on every request in this session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .alert("Save Prompt Preset", isPresented: $showingSavePreset) {
            TextField("Name", text: $newPresetName)
            Button("Save", action: saveCurrentPreset)
                .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the current system prompt to your library to reuse it in other sessions.")
        }
    }

    /// Live token estimate for the system prompt, plus the share of the context window
    /// it consumes (Ollama only — Apple Intelligence has no user-set context size here).
    /// The window is exactly `contextSize`, so the percentage is only as approximate as
    /// the token estimate itself.
    private var systemPromptCostLabel: String {
        let tokens = TokenEstimator.estimate(session.systemPrompt)
        var label = "~\(tokens) tokens"
        if profile.isChatBackend, !profile.isOnDevice, session.contextSize > 0 {
            let percent = Double(tokens) / Double(session.contextSize) * 100
            let pctText = percent > 0 && percent < 0.1
                ? "<0.1"
                : String(format: "%.1f", percent)
            label += " · ~\(pctText)% of context"
        }
        return label
    }

    private func saveCurrentPreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        modelContext.insert(PromptPreset(name: name, content: session.systemPrompt))
        newPresetName = ""
    }

    private func applyCustomContext() {
        if let value = Int(customContext.filter(\.isNumber)), value > 0 {
            session.contextSize = value
        }
        customContext = ""
    }

    /// Looks up the session model's trained context length so the picker can warn when
    /// the chosen size exceeds it.
    private func loadModelContext() async {
        modelMaxContext = nil
        modelSupportsThinking = nil
        guard session.backend == .ollama || session.backend == .llamaServer,
              !session.modelName.isEmpty,
              let client = serverBackend() else { return }
        let discovered = try? await client.modelContextLength(session.modelName)
        modelMaxContext = discovered
        // A llama.cpp server's window is fixed at launch; adopt it as the session's
        // context size so budgeting uses the real window (the user can't set it).
        if session.backend == .llamaServer, let discovered, discovered > 0 {
            session.contextSize = discovered
        }
        // Only Ollama reports per-model capabilities. Empty means "unknown" (keep the
        // reasoning control visible); a non-empty set without "thinking" means the model
        // can't reason, so hide the control — and clear a stale forced-On that would error.
        if session.backend == .ollama {
            let caps = (try? await client.modelCapabilities(session.modelName)) ?? []
            let known = caps.isEmpty ? nil : caps.contains("thinking")
            modelSupportsThinking = known
            if known == false, session.reasoningMode == .on {
                session.reasoningMode = .auto
            }
        }
    }

    /// Mirrors the session's stored parameters into the local text fields.
    private func loadParameterFields() {
        tempText = session.temperature.map { $0.formatted() } ?? ""
        topPText = session.topP.map { $0.formatted() } ?? ""
        topKText = session.topK.map(String.init) ?? ""
        repeatText = session.repeatPenalty.map { $0.formatted() } ?? ""
        seedText = session.seed.map(String.init) ?? ""
        stopText = session.stopSequences.joined(separator: ", ")
        maxTokensText = session.maxResponseTokens.map(String.init) ?? ""
    }

    private func clearGenerationParameters() {
        session.temperature = nil
        session.topP = nil
        session.topK = nil
        session.repeatPenalty = nil
        session.seed = nil
        session.stopSequences = []
        session.maxResponseTokens = nil
        loadParameterFields()
    }

    private func clearAppleParameters() {
        session.temperature = nil
        session.maxResponseTokens = nil
        session.appleSamplingMode = .automatic
        session.topK = nil
        session.topP = nil
        session.seed = nil
        loadParameterFields()
    }

    /// Parses a decimal, accepting a comma as the separator. Empty/invalid → nil.
    private func parseDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    private func parseInt(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        return digits.isEmpty ? nil : Int(digits)
    }

    private func loadModels() async {
        guard session.backend == .ollama || session.backend == .llamaServer else { return }
        guard let client = serverBackend() else {
            loadError = "Invalid server URL. Check Settings."
            return
        }
        loading = true
        loadError = nil
        do {
            let all = try await client.models()
            models = all
                .filter { !$0.isEmbeddingModel }
                .sorted { $0.name < $1.name }
            // Drop a selection that isn't valid for this backend (e.g. a leftover Ollama
            // model after switching to llama.cpp) so the picker never shows a phantom model.
            // llama.cpp serves one model, so adopt it; Ollama prompts for a fresh pick.
            let known = Set(models.map(\.name))
            let stale = !session.modelName.isEmpty && !known.contains(session.modelName)
            if session.backend == .llamaServer {
                if stale || session.modelName.isEmpty, let first = models.first {
                    session.modelName = first.name
                }
            } else if stale {
                session.modelName = ""
            }
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    /// The server backend for the session's engine, used for model listing and
    /// context-length lookups. Ollama and llama.cpp use different URLs and clients.
    private func serverBackend() -> (any ServerBackend)? {
        switch session.backend {
        case .ollama: return OllamaClient(baseURLString: serverURL)
        case .llamaServer: return LlamaServerClient(baseURLString: llamaServerURL)
        default: return nil
        }
    }

    /// Models that can accept image input (vision capability).
    private var visionModels: [OllamaModel] {
        models.filter(\.supportsVision)
    }

    /// Whether the chosen primary model can natively see images.
    private var primarySupportsVision: Bool {
        models.first(where: { $0.name == session.modelName })?.supportsVision ?? false
    }

    private var visionHelpText: String {
        if !session.visionModel.isEmpty {
            return "Multi-model: attached images are described by \(session.visionModel), then the description is sent to \(session.modelName.isEmpty ? "the primary model" : session.modelName)."
        }
        if primarySupportsVision {
            return "\(session.modelName) supports vision, so attached images are sent to it directly. Pick a vision model here to instead describe images with one model and reason with another."
        }
        return "Pick a vision model to enable image attachments: it describes images, and the description is sent to your primary model. (Your primary model can't accept images directly.)"
    }
}

/// A sheet that lists the text-to-image workflows you've run on the ComfyUI server (from its
/// history, already in API format) and imports the chosen one, auto-bound, into the library — no
/// manual export.
private struct ComfyServerImportSheet: View {
    let serverURL: String
    let onImport: (ComfyWorkflowTemplate) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var loading = true
    @State private var templates: [ComfyWorkflowTemplate] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Workflow from Server").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()
            content
        }
        .frame(width: 460, height: 460)
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView("Loading text-to-image workflows…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if templates.isEmpty {
            ContentUnavailableView("No text-to-image workflows", systemImage: "photo.on.rectangle.angled",
                                   description: Text("Run a text-to-image workflow in ComfyUI, then it'll show up here to import."))
        } else {
            List(templates) { template in
                Button {
                    onImport(template)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(template.name)
                            Text("\(template.parameters.count) parameters detected")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true
        if let client = ComfyUIClient(baseURLString: serverURL) {
            templates = await client.serverWorkflows()
        }
        loading = false
    }
}
