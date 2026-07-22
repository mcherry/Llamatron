import SwiftUI
import LlamaEngineStore
import LlamaEngine
import SwiftData

/// Root split view: sessions on the left, the selected conversation on the right.
/// On first launch it presents the setup sheet until a server is configured.
struct ContentView: View {
    @AppStorage(SettingsKey.didCompleteFirstRun) private var didCompleteFirstRun = false
    @AppStorage(SettingsKey.defaultContextSize) private var defaultContextSize = SettingsDefault.contextSize
    @AppStorage(SettingsKey.defaultModel) private var defaultModel = ""
    @AppStorage(SettingsKey.defaultBackend) private var defaultBackend = SettingsDefault.defaultBackend
    @AppStorage(SettingsKey.sessionPresets) private var sessionPresetsJSON = "[]"
    @AppStorage(SettingsKey.defaultPresetID) private var defaultPresetID = ""
    @AppStorage(SettingsKey.toolsFeatureEnabled) private var toolsFeatureEnabled = SettingsDefault.toolsFeatureEnabled

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatSession.updatedAt, order: .reverse) private var sessions: [ChatSession]
    @State private var selectedID: ChatSession.ID?
    @State private var sessionPendingDelete: ChatSession?
    /// iOS presents Settings as a sheet (there's no macOS-style Settings scene).
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedID) {
                ForEach(sessions) { session in
                    SessionRow(session: session) {
                        sessionPendingDelete = session
                    }
                    .contextMenu {
                        Button("New Chat Like This", systemImage: "plus.square.on.square") {
                            newSessionLike(session)
                        }
                        Button("Delete", role: .destructive) {
                            sessionPendingDelete = session
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 420)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    #if os(macOS)
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Program Settings")
                    #else
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Program Settings")
                    #endif

                    Button(action: newSession) {
                        Label("New Session", systemImage: "square.and.pencil")
                    }
                    .help("New Session")
                }
            }
            .confirmationDialog("Delete this session?",
                                isPresented: deletePresented,
                                presenting: sessionPendingDelete) { session in
                Button("Delete", role: .destructive) { delete(session) }
                Button("Cancel", role: .cancel) {}
            } message: { session in
                Text("\u{201c}\(session.title)\u{201d} and its messages will be permanently deleted.")
            }
        } detail: {
            if let id = selectedID, let session = sessions.first(where: { $0.id == id }) {
                ChatView(session: session)
                    .id(session.id)
            } else {
                ContentUnavailableView(
                    "No Session Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Create a session to start chatting.")
                )
            }
        }
        .sheet(isPresented: .constant(!didCompleteFirstRun)) {
            FirstRunView()
                .interactiveDismissDisabled()
        }
        #if os(iOS)
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
            }
        }
        #endif
        #if DEBUG
        .task {
            // Screenshot automation: seed anonymized content and select the hero.
            guard ScreenshotSeed.isActive, sessions.isEmpty else { return }
            selectedID = ScreenshotSeed.populate(modelContext)
        }
        #endif
    }

    private func newSession() {
        let session = makeSession()
        modelContext.insert(session)
        selectedID = session.id
    }

    /// Builds a new session from the default preset when one is chosen, otherwise from the
    /// App-default backend/model/context. Only Ollama uses a preset default model; llama.cpp
    /// auto-selects its single loaded model and Apple has none.
    private func makeSession() -> ChatSession {
        let session = ChatSession()
        if let preset = SessionPresetLibrary.preset(id: defaultPresetID, in: sessionPresetsJSON) {
            session.apply(preset.config)
        } else {
            let backend = BackendKind(rawValue: defaultBackend) ?? .ollama
            session.backend = backend
            session.modelName = backend == .ollama ? defaultModel : ""
            session.contextSize = defaultContextSize
        }
        seedDefaultTools(session)
        return session
    }

    /// When tool calling is enabled app-wide, a new chat starts with the *pure* tools
    /// (clock, render_graphic) already allowed — they auto-run and have no attack surface,
    /// so the common case works without per-chat setup. Network/local tools stay opt-in
    /// behind the confirmation gate. Only seeds an untouched session (respects a preset
    /// that configured tools).
    private func seedDefaultTools(_ session: ChatSession) {
        guard toolsFeatureEnabled, session.backend.profile.supportsTools,
              !session.toolsEnabled, session.allowedToolNames.isEmpty else { return }
        session.toolsEnabled = true
        session.allowedToolNames = ToolRegistry.builtInTools
            .filter { $0.riskTier == .pure }
            .map(\.name)
    }

    /// Creates a new session that copies an existing session's configuration (“new chat
    /// like this”) — same backend, model, prompt, and generation settings, empty transcript.
    private func newSessionLike(_ source: ChatSession) {
        let session = ChatSession()
        session.apply(source.configSnapshot())
        modelContext.insert(session)
        selectedID = session.id
    }

    /// Binding that drives the delete confirmation from the pending session.
    private var deletePresented: Binding<Bool> {
        Binding(get: { sessionPendingDelete != nil },
                set: { if !$0 { sessionPendingDelete = nil } })
    }

    private func delete(_ session: ChatSession) {
        if selectedID == session.id {
            selectedID = nil
        }
        modelContext.delete(session)
    }
}

private struct SessionRow: View {
    let session: ChatSession
    var onDelete: () -> Void
    @State private var hovering = alwaysRevealControls

    /// Backend-aware subtitle: the chosen Ollama model, or the engine name for
    /// Apple Intelligence (which has a single on-device model, so no picker).
    private var subtitle: String {
        switch session.backend {
        case .ollama:
            return session.modelName.isEmpty ? "No model set" : session.modelName
        case .llamaServer:
            return session.modelName.isEmpty ? BackendKind.llamaServer.label : session.modelName
        case .appleIntelligence:
            return BackendKind.appleIntelligence.label
        case .imageGeneration:
            return session.imageModel.isEmpty ? "No image model" : session.imageModel
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete session")
            // Revealed on hover so the list stays clean; the context menu remains a
            // fallback. Kept in layout (opacity) so rows don't resize on hover.
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .padding(.vertical, 2)
    }
}
