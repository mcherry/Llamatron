import SwiftUI
import LlamaEngine

/// Shown over the main window on first launch so the user picks and connects a backend
/// before using the app. "Get Started" stays disabled until the chosen backend is usable
/// (a successful server test, or Apple Intelligence being available), and the sheet can't
/// be dismissed until then. The chosen backend becomes the default for new chats.
struct FirstRunView: View {
    @AppStorage(SettingsKey.didCompleteFirstRun) private var didCompleteFirstRun = false
    @AppStorage(SettingsKey.serverURL) private var serverURL = SettingsDefault.serverURL
    @AppStorage(SettingsKey.llamaServerURL) private var llamaServerURL = SettingsDefault.llamaServerURL
    @AppStorage(SettingsKey.defaultBackend) private var defaultBackend = SettingsDefault.defaultBackend

    @State private var backend: BackendKind = .ollama
    @State private var testing = false
    @State private var statusText: String?
    @State private var succeeded = false

    /// Chat backends a user can start with (image generation is an optional add-on).
    private var choices: [BackendKind] { BackendKind.allCases.filter { $0.profile.isChatBackend } }
    private var needsServer: Bool { backend.profile.needsServerURL }
    private var serverBinding: Binding<String> { backend == .llamaServer ? $llamaServerURL : $serverURL }
    private var placeholder: String { backend == .llamaServer ? "http://localhost:8080" : "http://localhost:11434" }

    private var canStart: Bool {
        backend == .appleIntelligence ? AppleIntelligence.isAvailable : succeeded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Llamatron")
                .font(.title2).bold()
            Text("Choose how Llamatron should talk to a model. You can change this or add other backends any time in Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Engine", selection: $backend) {
                ForEach(choices) { Text($0.label).tag($0) }
            }
            .onChange(of: backend) { resetStatus() }

            if needsServer {
                VStack(alignment: .leading, spacing: 8) {
                    Text(backend == .llamaServer ? "llama.cpp Server" : "Ollama Server")
                        .font(.headline)
                    TextField(placeholder, text: serverBinding)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    HStack(spacing: 8) {
                        Button("Test Connection") { Task { await runTest() } }
                            .disabled(testing || serverBinding.wrappedValue.isEmpty)
                        if testing { ProgressView().controlSize(.small) }
                        if let statusText {
                            Label(statusText, systemImage: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(succeeded ? .green : .red)
                                .font(.caption).lineLimit(2)
                        }
                    }
                }
            } else {
                Label(AppleIntelligence.statusMessage,
                      systemImage: AppleIntelligence.isAvailable ? "checkmark.seal" : "info.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Get Started") {
                    defaultBackend = backend.rawValue
                    didCompleteFirstRun = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 480)
        #endif
    }

    private func resetStatus() {
        statusText = nil
        succeeded = false
    }

    private func runTest() async {
        testing = true
        statusText = nil
        defer { testing = false }
        switch backend {
        case .ollama:
            switch await ServerProbe.checkVersion(baseURL: serverURL) {
            case .success(let version):
                succeeded = true
                statusText = "Connected to Ollama \(version)."
            case .failure(let reason):
                succeeded = false
                statusText = reason
            }
        case .llamaServer:
            guard let client = LlamaServerClient(baseURLString: llamaServerURL) else {
                succeeded = false
                statusText = "That doesn't look like a valid URL."
                return
            }
            do {
                let models = try await client.models()
                succeeded = true
                statusText = models.first.map { "Connected \u{00b7} \($0.name)" } ?? "Connected."
            } catch {
                succeeded = false
                statusText = error.localizedDescription
            }
        default:
            break
        }
    }
}
