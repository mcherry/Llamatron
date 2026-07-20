import SwiftUI
import LlamaEngineStore
import LlamaEngine
import SwiftData
import UniformTypeIdentifiers
import UniformTypeIdentifiers
import AppKit

/// The chat detail pane: a header strip with the session's model/context, the
/// streaming transcript, attachment chips, an inline error banner, and the composer.
struct ChatView: View {
    @Bindable var session: ChatSession

    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.serverURL) private var serverURL = SettingsDefault.serverURL
    @AppStorage(SettingsKey.llamaServerURL) private var llamaServerURL = SettingsDefault.llamaServerURL
    @AppStorage(SettingsKey.requestTimeout) private var requestTimeout = SettingsDefault.timeout
    @AppStorage(SettingsKey.diagramGuidance) private var diagramGuidance = false
    @AppStorage(SettingsKey.rightSizeContext) private var rightSizeContext = SettingsDefault.rightSizeContext
    @AppStorage(SettingsKey.keepAliveMinutes) private var keepAliveMinutes = SettingsDefault.keepAliveMinutes
    @AppStorage(SettingsKey.imageServerURL) private var imageServerURL = SettingsDefault.imageServerURL
    @AppStorage(SettingsKey.imageBackendKind) private var imageBackendKind = ImageBackendKind.easyDiffusion.rawValue
    @AppStorage(SettingsKey.comfyTemplates) private var comfyTemplatesJSON = "[]"
    @AppStorage(SettingsKey.ttsAppleVoice) private var ttsAppleVoice = ""
    @AppStorage(SettingsKey.ttsServerURL) private var ttsServerURL = SettingsDefault.ttsServerURL
    @AppStorage(SettingsKey.ttsVoice) private var ttsVoice = ""
    @AppStorage(SettingsKey.ttsSpeed) private var ttsSpeed = SettingsDefault.ttsSpeed
    @AppStorage(SettingsKey.dictationAutoSend) private var dictationAutoSend = false
    @AppStorage(SettingsKey.dictationPauseSeconds) private var dictationPauseSeconds = SettingsDefault.dictationPauseSeconds
    @AppStorage(SettingsKey.conversationMode) private var conversationModeEnabled = false
    @AppStorage(SettingsKey.ttsFeatureEnabled) private var ttsFeatureEnabled = SettingsDefault.ttsFeatureEnabled
    @AppStorage(SettingsKey.sttFeatureEnabled) private var sttFeatureEnabled = SettingsDefault.sttFeatureEnabled
    @AppStorage(SettingsKey.webSearchEnabled) private var webSearchEnabled = SettingsDefault.webSearchEnabled
    @AppStorage(SettingsKey.dictationVoiceProcessing) private var voiceProcessing = SettingsDefault.dictationVoiceProcessing

    @State private var viewModel = ConversationController()
    @State private var speech = SpeechController()
    @State private var dictation = DictationController()
    /// The draft text captured when dictation started, so the transcript appends to it.
    @State private var dictationBase = ""
    /// True while always-on conversation mode is active for this session.
    @State private var conversationActive = false
    /// True while an auto-TTS reply is generating, so its text is held hidden until
    /// narration begins.
    @State private var narrationArmed = false
    @State private var draft = ""
    @State private var showingConfig = false
    @State private var showingImporter = false
    @State private var showingFolderImporter = false
    @State private var showingAddWebSource = false
    @State private var showingWebSearch = false
    @State private var showingResetConfirm = false
    @State private var exportDocument: TextExportDocument?
    @State private var exportContentType: UTType = .plainText
    @State private var exportName = "session"
    @State private var showingExporter = false
    /// 0...1 while a large attachment is being chunked/indexed; nil when idle.
    @State private var indexingProgress: Double?
    /// Human-readable status shown in the indexing bar (e.g. per-file progress for a
    /// directory source); nil falls back to a generic percentage.
    @State private var indexingLabel: String?
    @FocusState private var titleFocused: Bool

    private let bottomAnchor = "bottom-anchor"

    private var visibleMessages: [ChatMessage] {
        session.orderedMessages.filter { $0.role != .system }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && session.isConfigured
            && !viewModel.isStreaming
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            if let status = viewModel.activityStatus {
                activityBar(status)
            }
            if let progress = indexingProgress {
                indexingBar(progress)
            }
            if let info = viewModel.contextInfo {
                contextInfoBar(info)
            }
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
            if !session.attachments.isEmpty {
                attachmentsBar
            }
            composer
            Divider()
            StatusBarView(session: session, isStreaming: viewModel.isStreaming)
        }
        .sheet(isPresented: $showingConfig) {
            SessionConfigView(session: session, serverURL: serverURL)
        }
        .sheet(isPresented: $showingAddWebSource) {
            AddWebSourceView { title, content in
                addWebSource(title: title, content: content)
            }
        }
        .sheet(isPresented: $showingWebSearch) {
            WebSearchView { title, content in
                addWebSource(title: title, content: content)
            }
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: AttachmentLoader.importTypes,
                      allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .fileImporter(isPresented: $showingFolderImporter,
                      allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            handleFolderImport(result)
        }
        .dropDestination(for: URL.self) { urls, _ in
            importURLs(urls)
            return true
        }
        .task(id: serverURL) { await loadVisionCapabilities() }
        .task(id: session.modelName) { await loadModelContextLength() }
        .task(id: session.backend) { await resolveLlamaServerSession() }
        .onDisappear {
            speech.stop()
            dictation.stop()
        }
        .onChange(of: viewModel.isStreaming) { wasStreaming, nowStreaming in
            guard wasStreaming, !nowStreaming else { return }
            handleStreamFinished()
        }
        .onChange(of: speech.narratingMessageID) { _, id in
            // Once narration actually starts, playback progress drives the reveal, so
            // the generation-time hold is no longer needed.
            if id != nil { narrationArmed = false }
        }
        .onChange(of: speech.speakingMessageID) { _, id in
            // A spoken reply finished — in conversation mode, resume listening.
            if id == nil { maybeResumeConversation() }
        }
        .onChange(of: speech.saveError) { _, message in
            if let message {
                viewModel.errorMessage = message
                speech.saveError = nil
            }
        }
        .confirmationDialog("Start a fresh chat?",
                            isPresented: $showingResetConfirm,
                            titleVisibility: .visible) {
            Button("Reset Session", role: .destructive, action: reset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all messages and stats and renames the session, but keeps its model, settings, and attached files.")
        }
        .fileExporter(isPresented: $showingExporter,
                      document: exportDocument,
                      contentType: exportContentType,
                      defaultFilename: exportName) { _ in }
    }

    private var composer: some View {
        composerBase
            .onChange(of: dictation.transcript) { _, text in
                // Live dictation owns the draft while listening: append to what was there.
                if dictation.isListening {
                    draft = DictationController.composed(base: dictationBase, transcript: text)
                }
            }
            .onChange(of: dictation.autoSendTick) { _, _ in
                // A speech pause finished an utterance; submit hands-free if we can.
                if canSend { send() }
            }
            .onChange(of: dictation.errorMessage) { _, message in
                if let message {
                    viewModel.errorMessage = message
                    dictation.clearError()
                }
            }
    }

    private var composerBase: some View {
        Composer(text: $draft,
                 isStreaming: viewModel.isStreaming,
                 canSend: canSend,
                 onSend: send,
                 onStop: viewModel.stop,
                 onAttach: { showingImporter = true },
                 onAttachFolder: { showingFolderImporter = true },
                 onAddWebSource: webSearchEnabled ? { showingAddWebSource = true } : nil,
                 onWebSearch: webSearchEnabled ? { showingWebSearch = true } : nil,
                 onMic: conversationActive ? nil : micAction,
                 isDictating: dictation.isListening,
                 dictationUnavailable: dictation.isUnavailable,
                 onConversation: conversationAction,
                 conversationActive: conversationActive)
    }

    /// The mic toggle, or `nil` when speech recognition isn't available.
    private var micAction: (() -> Void)? {
        guard sttFeatureEnabled, dictation.isSupported else { return nil }
        return { toggleDictation() }
    }

    /// The conversation toggle, or `nil` when the feature is off or unsupported.
    private var conversationAction: (() -> Void)? {
        guard sttFeatureEnabled, conversationModeEnabled, dictation.isSupported else { return nil }
        return { toggleConversation() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Session title", text: $session.title)
                .textFieldStyle(.plain)
                .font(.headline)
                .focused($titleFocused)
                .onChange(of: session.title) {
                    // Count it as a manual rename only when the user is actually
                    // editing the field, so programmatic changes (auto-naming, reset)
                    // don't flip the session out of auto-naming.
                    if titleFocused { session.titleIsAuto = false }
                }

            Spacer()

            Button {
                showingConfig = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: session.backend.systemImage)
                    Text(engineLabel)
                    if session.backend == .ollama || session.backend == .llamaServer {
                        Text("·")
                        Text(ContextSize.label(session.contextSize))
                    }
                }
                .font(.caption)
            }
            .buttonStyle(.bordered)
            .help("Session settings")

            Button {
                showingResetConfirm = true
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .help("Reset session (clear messages, keep settings)")
            .disabled(session.messages.isEmpty && session.titleIsAuto)

            Menu {
                Button("Export as Markdown…") { startExport(.markdown) }
                Button("Export as JSON…") { startExport(.json) }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Export conversation")
            .disabled(visibleMessages.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if visibleMessages.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleMessages) { message in
                            MessageRow(message: message,
                                       isGenerating: isGenerating(message),
                                       isSpeaking: speech.speakingMessageID == message.id,
                                       onToggleSpeak: speakEnabled(message) ? { toggleSpeak(message) } : nil,
                                       isSaving: speech.savingMessageID == message.id,
                                       onSaveAudio: speakEnabled(message) ? { saveAudio(message) } : nil,
                                       onRegenerate: regenerateEnabled(message) ? { regenerate(message) } : nil,
                                       revealedCharacters: revealedCharacters(for: message))
                                .id(message.id)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding()
            }
            .onChange(of: streamingTick) {
                // Pin to the bottom without animating: starting a fresh 0.15s scroll
                // animation on every streamed token overlaps the previous one, which
                // overshoots the bottom and looks jittery. An instant snap follows the
                // stream smoothly.
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
            .onChange(of: viewModel.isStreaming) { _, streaming in
                // When the reply finishes, its final layout can be taller than the streamed
                // text was (the caption appears, code blocks / tables / diagrams settle), so
                // re-pin to the bottom on the next layout pass — otherwise the tail is left
                // hidden below the fold.
                guard !streaming else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: speech.narrationProgress) {
                // Keep the revealing narrated reply in view as it plays.
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: visibleMessages.count) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .onAppear {
                // Jump to the latest message when the session opens. Deferred so the
                // lazy transcript content is laid out before we scroll.
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    /// Drives autoscroll: the in-flight assistant message grows as tokens (answer or
    /// reasoning) stream in.
    private var streamingTick: Int {
        guard let last = visibleMessages.last else { return 0 }
        return last.content.count + last.thinking.count
    }

    /// True for the assistant reply currently streaming (the last message while the
    /// view model is streaming), so its caption stays hidden until it finishes.
    private func isGenerating(_ message: ChatMessage) -> Bool {
        viewModel.isStreaming
            && message.role == .assistant
            && message.id == visibleMessages.last?.id
    }

    /// Header label for the active engine.
    private var engineLabel: String {
        switch session.backend {
        case .ollama:
            return session.modelName.isEmpty ? "Choose model" : session.modelName
        case .llamaServer:
            return session.modelName.isEmpty ? "llama.cpp" : session.modelName
        case .appleIntelligence:
            return BackendKind.appleIntelligence.label
        case .imageGeneration:
            return session.imageModel.isEmpty ? "Choose image model" : session.imageModel
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(session.isConfigured
                 ? "Send a message to start the conversation."
                 : "Choose a model to start chatting.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                viewModel.dismissError()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Context info + attachments

    private func activityBar(_ status: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "stopwatch")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let started = viewModel.generationStartedAt {
                Text(timerInterval: started...Date.distantFuture, countsDown: false, showsHours: false)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.purple.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private func contextInfoBar(_ info: ContextInfo) -> some View {
        let isWarning = info.warning != nil
        return HStack(spacing: 6) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "doc.text.magnifyingglass")
                .foregroundStyle(isWarning ? .orange : .secondary)
            Text(info.warning ?? info.note ?? info.summary)
                .font(.caption)
                .foregroundStyle(isWarning ? .primary : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(info.strategy.label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((isWarning ? Color.orange : Color.blue).opacity(isWarning ? 0.12 : 0.08),
                    in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var attachmentsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(session.orderedAttachments) { attachment in
                    attachmentChip(attachment)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func attachmentChip(_ attachment: Attachment) -> some View {
        HStack(spacing: 5) {
            if attachment.isImage, let data = attachment.imageData,
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else if attachment.isDirectory {
                Image(systemName: "folder")
                    .font(.caption2)
            } else {
                Image(systemName: "doc.text")
                    .font(.caption2)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.fileName)
                    .font(.caption)
                    .lineLimit(1)
                Text(attachment.isImage ? "image"
                     : attachment.isDirectory ? "\(attachment.fileCount) files · ~\(attachment.tokenEstimate.formatted()) tokens"
                     : "~\(attachment.tokenEstimate.formatted()) tokens")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                modelContext.delete(attachment)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove attachment")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func send() {
        // The client may be nil (e.g. a blank server URL); that's fine for an Apple
        // Intelligence session. The view model validates what each backend needs.
        dictation.stop()
        let client = sessionServerBackend()
        let text = draft
        draft = ""
        speech.stop()
        // Hold the upcoming reply hidden until narration starts, when auto-TTS is on.
        narrationArmed = narrationEngineReady
        viewModel.send(text: text,
                       session: session,
                       client: client,
                       diagramGuidance: diagramGuidance,
                       rightSizeContext: rightSizeContext,
                       keepAliveMinutes: keepAliveMinutes,
                       imageServerURL: imageServerURL,
                       imageBackendKind: imageBackendKind,
                       imageWorkflowTemplate: selectedComfyTemplate,
                       modelContext: modelContext)
    }

    /// Whether a per-message "read aloud" button should appear: TTS is on for this chat
    /// and the message is a non-empty assistant reply.
    private func speakEnabled(_ message: ChatMessage) -> Bool {
        ttsFeatureEnabled && session.ttsEnabled && message.role == .assistant && !message.content.isEmpty
    }

    private var ttsConfig: SpeechController.Config {
        SpeechController.Config(engine: session.ttsEngine,
                               appleVoice: ttsAppleVoice,
                               serverURL: ttsServerURL,
                               serverVoice: ttsVoice,
                               speed: ttsSpeed)
    }

    private func toggleSpeak(_ message: ChatMessage) {
        speech.toggle(messageID: message.id, text: message.content, config: ttsConfig)
    }

    /// Toggles speech-to-text: dictation streams into the draft; the user (or, with
    /// auto-send, a pause) submits it.
    private func toggleDictation() {
        if dictation.isListening {
            dictation.stop()
        } else {
            dictationBase = draft
            dictation.autoSend = dictationAutoSend
            dictation.silenceSeconds = dictationPauseSeconds
            dictation.useVoiceProcessing = voiceProcessing
            dictation.start()
        }
    }

    /// Toggles always-on, hands-free conversation mode for this session.
    private func toggleConversation() {
        if conversationActive {
            conversationActive = false
            dictation.stop()
        } else {
            conversationActive = true
            startConversationTurn()
        }
    }

    /// Opens the mic for the next conversation turn, if nothing else is in progress.
    private func startConversationTurn() {
        guard conversationActive, !dictation.isListening, !viewModel.isStreaming,
              speech.speakingMessageID == nil else { return }
        dictationBase = ""
        dictation.autoSend = true
        dictation.silenceSeconds = dictationPauseSeconds
        dictation.useVoiceProcessing = voiceProcessing
        dictation.start()
    }

    /// Resumes listening after a reply (and any spoken playback) finishes.
    private func maybeResumeConversation() {
        guard conversationActive else { return }
        guard viewModel.errorMessage == nil else {
            conversationActive = false   // an error stopped the flow; leave conversation
            return
        }
        guard !viewModel.isStreaming, speech.speakingMessageID == nil, !dictation.isListening,
              draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        startConversationTurn()
    }

    /// Called when a streaming reply finishes: narrate it for auto-TTS, then (in
    /// conversation mode) resume listening once any spoken reply is done.
    private func handleStreamFinished() {
        if narrationArmed {
            if session.ttsEnabled, session.ttsAutoSpeak, viewModel.errorMessage == nil,
               let last = visibleMessages.last, last.role == .assistant, !last.content.isEmpty {
                speech.speak(messageID: last.id, text: last.content, config: ttsConfig, narrate: true)
            } else {
                narrationArmed = false   // nothing to narrate — reveal the reply normally
            }
        }
        if conversationActive { maybeResumeConversation() }
    }

    /// Whether auto-TTS will narrate replies (Apple is always ready; the server needs a
    /// URL + voice). When true, a generating reply is held hidden until its audio plays.
    private var narrationEngineReady: Bool {
        guard ttsFeatureEnabled, session.ttsEnabled, session.ttsAutoSpeak else { return false }
        switch session.ttsEngine {
        case .apple: return true
        case .server: return TTS.isConfigured(enabled: true, serverURL: ttsServerURL) && !ttsVoice.isEmpty
        }
    }

    /// How much of a reply to reveal: the whole thing normally; nothing while a narrated
    /// reply is buffered; a growing prefix as its audio plays.
    private func revealedCharacters(for message: ChatMessage) -> Int? {
        guard message.role == .assistant else { return nil }
        if speech.narratingMessageID == message.id {
            return SpeechController.revealedCount(progress: speech.narrationProgress,
                                                  total: message.content.count)
        }
        if narrationArmed && message.id == visibleMessages.last?.id {
            return 0
        }
        return nil
    }

    /// Whether the inspector should offer "Regenerate" for this image reply.
    private func regenerateEnabled(_ message: ChatMessage) -> Bool {
        session.backend == .imageGeneration && message.imageGenInfo != nil && !viewModel.isStreaming
    }

    /// The ComfyUI workflow template this session selected (only when the image backend is ComfyUI).
    private var selectedComfyTemplate: ComfyWorkflowTemplate? {
        guard ImageBackendKind(rawValue: imageBackendKind) == .comfyUI else { return nil }
        return ComfyTemplateLibrary.template(id: session.comfyTemplateID, in: comfyTemplatesJSON)
    }

    private func regenerate(_ message: ChatMessage) {
        viewModel.regenerateImage(from: message,
                                  session: session,
                                  serverURL: imageServerURL,
                                  backendKindRaw: imageBackendKind,
                                  imageWorkflowTemplate: selectedComfyTemplate,
                                  modelContext: modelContext)
    }

    private func saveAudio(_ message: ChatMessage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m4a") ?? .audio]
        panel.nameFieldStringValue = "reply.m4a"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        speech.saveAudio(messageID: message.id, text: message.content, config: ttsConfig, to: url)
    }

    private enum ExportFormat { case markdown, json }

    /// Builds the export document for the chosen format and presents the save panel.
    private func startExport(_ format: ExportFormat) {
        let snapshot = session.exportSnapshot()
        let safeName = session.title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        exportName = safeName.isEmpty ? "session" : safeName

        switch format {
        case .markdown:
            exportContentType = .plainText
            exportDocument = TextExportDocument(text: SessionExporter.markdown(snapshot),
                                                contentType: .plainText)
        case .json:
            exportContentType = .json
            exportDocument = TextExportDocument(text: SessionExporter.json(snapshot),
                                                contentType: .json)
        }
        showingExporter = true
    }

    /// Clears the conversation and stats for a fresh start, keeping the session's
    /// configuration (model, backend, context size, system prompt) and attachments.
    /// The title returns to auto so the next prompt regenerates it.
    private func reset() {
        viewModel.stop()
        for message in session.orderedMessages {
            modelContext.delete(message)
        }
        session.title = "New Session"
        session.titleIsAuto = true
        session.updatedAt = .now
        session.historySummary = ""
        session.summarizedUntil = nil
        draft = ""
        viewModel.contextInfo = nil
        viewModel.resetContextSizing(for: session)
        viewModel.dismissError()
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            importURLs(urls)
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    /// The remote LLM server for this session. llama.cpp sessions talk to the
    /// llama-server URL; every other backend uses the Ollama URL — which Ollama
    /// sessions use for chat + retrieval and Apple Intelligence sessions use for
    /// retrieval embeddings only.
    private func sessionServerBackend() -> (any ServerBackend)? {
        switch session.backend {
        case .llamaServer:
            return LlamaServerClient(baseURLString: llamaServerURL, timeout: TimeInterval(requestTimeout))
        default:
            return OllamaClient(baseURLString: serverURL, timeout: TimeInterval(requestTimeout))
        }
    }

    /// Loads which server models support vision, so the controller can choose the
    /// native-vision vs. preprocessor path when an image is attached.
    private func loadVisionCapabilities() async {
        await viewModel.loadVisionCapabilities(client: sessionServerBackend())
    }

    /// Looks up the session model's trained context length so budgeting
    /// and `num_ctx` respect the model's real limit instead of the user's raw preset.
    private func loadModelContextLength() async {
        await viewModel.loadModelContextLength(for: session,
                                               client: sessionServerBackend())
    }

    /// For a llama.cpp session, adopt the server's loaded model and its launch-fixed
    /// (`-c`) context window so the header, budgeting, and retrieval use the real values
    /// without the user having to open Session Settings first. Otherwise a fresh chat
    /// keeps the 32K default, which mismatches the server and mis-sizes large sources.
    private func resolveLlamaServerSession() async {
        guard session.backend == .llamaServer,
              let client = LlamaServerClient(baseURLString: llamaServerURL,
                                             timeout: TimeInterval(requestTimeout)) else { return }
        if session.modelName.isEmpty, let first = try? await client.models().first {
            session.modelName = first.name
        }
        if let window = try? await client.modelContextLength(session.modelName), window > 0 {
            session.contextSize = window
        }
    }

    private func importURLs(_ urls: [URL]) {
        Task { @MainActor in
            indexingProgress = 0
            defer { indexingProgress = nil }
            for url in urls {
                do {
                    try await AttachmentLoader.load(from: url, into: session,
                                                    modelContext: modelContext) { indexingProgress = $0 }
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first { indexDirectory(url) }
        case .failure(let error):
            viewModel.errorMessage = error.localizedDescription
        }
    }

    /// Indexes a whole folder as one retrievable source. The walk/chunk work runs off the
    /// main actor inside `AttachmentLoader`; here we just drive the progress bar and surface
    /// per-file status so a large repo doesn't look like a frozen spinner.
    private func indexDirectory(_ url: URL) {
        Task { @MainActor in
            indexingProgress = 0
            indexingLabel = "Scanning…"
            defer { indexingProgress = nil; indexingLabel = nil }
            do {
                try await AttachmentLoader.indexDirectory(at: url, into: session,
                                                          modelContext: modelContext) { label, progress in
                    indexingLabel = label.isEmpty ? nil : label
                    indexingProgress = progress
                }
                session.updatedAt = .now
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    /// Stores a fetched web page or pasted note as a retrievable text attachment, so it
    /// rides the existing retrieval pipeline like any other attached file.
    private func addWebSource(title: String, content: String) {        Task { @MainActor in
            indexingProgress = 0
            defer { indexingProgress = nil }
            await AttachmentLoader.makeTextAttachment(name: title.isEmpty ? "Source" : title,
                                                      text: content,
                                                      into: session,
                                                      modelContext: modelContext) { indexingProgress = $0 }
            session.updatedAt = .now
        }
    }

    /// A thin progress bar shown while a large source is chunked and indexed in batches.
    private func indexingBar(_ progress: Double) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text(indexingLabel ?? "Indexing… \(Int(progress * 100))%")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }
}
