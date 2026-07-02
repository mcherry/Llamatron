import SwiftUI

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

    // Local text mirrors of the optional numeric parameters, so typing ("0.") doesn't
    // get reformatted mid-edit. Committed to the session on change.
    @State private var tempText = ""
    @State private var topPText = ""
    @State private var topKText = ""
    @State private var repeatText = ""
    @State private var seedText = ""
    @State private var stopText = ""
    @State private var maxTokensText = ""

    @AppStorage(SettingsKey.imageGenEnabled) private var imageGenEnabled = false
    @AppStorage(SettingsKey.imageServerURL) private var imageServerURL = SettingsDefault.imageServerURL
    @AppStorage(SettingsKey.imageBackendKind) private var imageBackendKind = ImageBackendKind.easyDiffusion.rawValue
    @State private var imageModels: [ImageModel] = []
    @State private var imageTesting = false
    @State private var imageLoadError: String?

    /// Shared width for the generation parameter entry fields.
    private let fieldWidth: CGFloat = 160

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Session Settings").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            Form {
                backendSection
                if session.backend == .ollama {
                    modelSection
                    visionSection
                    contextSection
                    generationSection
                }
                if session.backend == .appleIntelligence {
                    appleGenerationSection
                }
                if session.backend == .imageGeneration {
                    imageSection
                }
                if session.backend != .imageGeneration {
                    historySection
                    contextStrategySection
                    systemPromptSection
                    speechSection
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 470, height: 620)
        .task { await loadModels() }
        .task(id: session.backend) {
            if session.backend == .imageGeneration { await loadImageModels() }
        }
        .task(id: session.modelName) { await loadModelContext() }
        .onAppear(perform: loadParameterFields)
    }

    private var backendSection: some View {
        Section("Backend") {
            Picker("Engine", selection: $session.backend) {
                Text(BackendKind.ollama.label).tag(BackendKind.ollama)
                // Offer Apple Intelligence only when the system reports it available,
                // but keep an already-chosen value visible so it isn't silently reset.
                if appleStatus == .available || session.backend == .appleIntelligence {
                    Text(BackendKind.appleIntelligence.label).tag(BackendKind.appleIntelligence)
                }
                if imageGenEnabled || session.backend == .imageGeneration {
                    Text(BackendKind.imageGeneration.label).tag(BackendKind.imageGeneration)
                }
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

    private var generationSection: some View {
        Section("Generation") {
            Picker("Reasoning", selection: $session.reasoningMode) {
                ForEach(ReasoningMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text("Reasoning models (deepseek-r1, qwen3) show their thinking in a collapsible section. Automatic uses the model's default; turn it Off to hide it. Forcing it On errors on models that don't support thinking.")
                .font(.caption)
                .foregroundStyle(.secondary)

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

    /// A small "i" info icon with a hover tooltip describing the adjacent field.
    private func infoButton(_ help: String) -> some View {
        Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .help(help)
    }

    private var imageSection: some View {
        Section("Image Generation") {
            if !imageGenEnabled {
                Label("Turn on image generation in Settings, then pick a model here.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
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
            if session.imageModel.isEmpty, let first = fetched.first { session.imageModel = first.id }
            if fetched.isEmpty { imageLoadError = "Connected, but found no image models." }
        } catch {
            imageLoadError = (error as? LocalizedError)?.errorDescription ?? "Couldn't reach the image server."
        }
        imageTesting = false
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
                .menuStyle(.borderlessButton)
                .fixedSize()

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
        if session.backend == .ollama, session.contextSize > 0 {
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
        guard session.backend == .ollama, !session.modelName.isEmpty,
              let client = OllamaClient(baseURLString: serverURL) else { return }
        modelMaxContext = try? await client.modelContextLength(session.modelName)
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
        guard let client = OllamaClient(baseURLString: serverURL) else {
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
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
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
