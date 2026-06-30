import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UniformTypeIdentifiers

/// The chat detail pane: a header strip with the session's model/context, the
/// streaming transcript, attachment chips, an inline error banner, and the composer.
struct ChatView: View {
    @Bindable var session: ChatSession

    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.serverURL) private var serverURL = SettingsDefault.serverURL
    @AppStorage(SettingsKey.requestTimeout) private var requestTimeout = SettingsDefault.timeout
    @AppStorage(SettingsKey.embeddingModel) private var embeddingModel = SettingsDefault.embeddingModel
    @AppStorage(SettingsKey.diagramGuidance) private var diagramGuidance = false
    @AppStorage(SettingsKey.imageServerURL) private var imageServerURL = SettingsDefault.imageServerURL
    @AppStorage(SettingsKey.imageBackendKind) private var imageBackendKind = ImageBackendKind.easyDiffusion.rawValue
    @AppStorage(SettingsKey.ttsAppleVoice) private var ttsAppleVoice = ""
    @AppStorage(SettingsKey.ttsServerURL) private var ttsServerURL = SettingsDefault.ttsServerURL
    @AppStorage(SettingsKey.ttsVoice) private var ttsVoice = ""
    @AppStorage(SettingsKey.ttsSpeed) private var ttsSpeed = SettingsDefault.ttsSpeed

    @State private var viewModel = ChatViewModel()
    @State private var speech = SpeechController()
    @State private var draft = ""
    @State private var showingConfig = false
    @State private var showingImporter = false
    @State private var showingAddWebSource = false
    @State private var showingWebSearch = false
    @State private var showingResetConfirm = false
    @State private var exportDocument: TextExportDocument?
    @State private var exportContentType: UTType = .plainText
    @State private var exportName = "session"
    @State private var showingExporter = false
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
            if let info = viewModel.contextInfo {
                contextInfoBar(info)
            }
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
            if !session.attachments.isEmpty {
                attachmentsBar
            }
            Composer(text: $draft,
                     isStreaming: viewModel.isStreaming,
                     canSend: canSend,
                     onSend: send,
                     onStop: viewModel.stop,
                     onAttach: { showingImporter = true },
                     onAddWebSource: { showingAddWebSource = true },
                     onWebSearch: { showingWebSearch = true })
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
        .dropDestination(for: URL.self) { urls, _ in
            importURLs(urls)
            return true
        }
        .task(id: serverURL) { await loadVisionCapabilities() }
        .onDisappear { speech.stop() }
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
                    if session.backend == .ollama {
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
                                       onToggleSpeak: speakEnabled(message) ? { toggleSpeak(message) } : nil)
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
            ProgressView().controlSize(.small)
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
            } else {
                Image(systemName: "doc.text")
                    .font(.caption2)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.fileName)
                    .font(.caption)
                    .lineLimit(1)
                Text(attachment.isImage ? "image" : "~\(attachment.tokenEstimate.formatted()) tokens")
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
        let client = OllamaClient(baseURLString: serverURL,
                                  timeout: TimeInterval(requestTimeout))
        let text = draft
        draft = ""
        viewModel.send(text: text,
                       session: session,
                       client: client,
                       embeddingModel: embeddingModel,
                       diagramGuidance: diagramGuidance,
                       imageServerURL: imageServerURL,
                       imageBackendKind: imageBackendKind,
                       modelContext: modelContext)
    }

    /// Whether a per-message "read aloud" button should appear: TTS is on for this chat
    /// and the message is a non-empty assistant reply.
    private func speakEnabled(_ message: ChatMessage) -> Bool {
        session.ttsEnabled && message.role == .assistant && !message.content.isEmpty
    }

    private func toggleSpeak(_ message: ChatMessage) {
        let config = SpeechController.Config(engine: session.ttsEngine,
                                             appleVoice: ttsAppleVoice,
                                             serverURL: ttsServerURL,
                                             serverVoice: ttsVoice,
                                             speed: ttsSpeed)
        speech.toggle(messageID: message.id, text: message.content, config: config)
    }

    private enum ExportFormat { case markdown, json }

    /// Builds the export document for the chosen format and presents the save panel.
    private func startExport(_ format: ExportFormat) {
        let snapshot = SessionExporter.Session(
            title: session.title,
            backend: session.backend.label,
            model: session.modelName,
            contextSize: session.contextSize,
            systemPrompt: session.systemPrompt,
            createdAt: session.createdAt,
            turns: session.orderedMessages
                .filter { $0.role != .system }
                .map { msg in
                    SessionExporter.Turn(role: msg.role.rawValue,
                                         content: msg.content,
                                         thinking: msg.thinking,
                                         createdAt: msg.createdAt,
                                         promptTokens: msg.promptTokens,
                                         evalTokens: msg.evalTokens,
                                         generationSeconds: msg.generationSeconds,
                                         firstTokenSeconds: msg.firstTokenSeconds)
                }
        )
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

    /// Loads which server models support vision, so the view model can choose the
    /// native-vision vs. preprocessor path when an image is attached.
    private func loadVisionCapabilities() async {
        guard let client = OllamaClient(baseURLString: serverURL) else { return }
        if let models = try? await client.models() {
            viewModel.availableVisionModelNames = Set(models.filter(\.supportsVision).map(\.name))
        }
    }

    private func importURLs(_ urls: [URL]) {
        for url in urls {
            do {
                try AttachmentLoader.load(from: url, into: session, modelContext: modelContext)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    /// Stores a fetched web page or pasted note as a retrievable text attachment, so it
    /// rides the existing retrieval pipeline like any other attached file.
    private func addWebSource(title: String, content: String) {
        AttachmentLoader.makeTextAttachment(name: title.isEmpty ? "Source" : title,
                                            text: content,
                                            into: session,
                                            modelContext: modelContext)
        session.updatedAt = .now
    }
}
