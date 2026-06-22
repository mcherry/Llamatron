import SwiftUI

/// Server address field plus a live "Test Connection" button. Shared by the
/// first-run setup and the Settings window so the logic lives in one place.
struct ServerSettingsForm: View {
    @AppStorage(SettingsKey.serverURL) private var serverURL = SettingsDefault.serverURL
    @State private var testing = false
    @State private var statusText: String?
    @State private var succeeded = false

    /// Called after each test with whether the server answered. The first-run flow
    /// uses this to enable its "Get Started" button.
    var onVerified: ((Bool) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ollama Server")
                .font(.headline)
            TextField("http://localhost:11434", text: $serverURL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            HStack(spacing: 8) {
                Button("Test Connection") {
                    Task { await runTest() }
                }
                .disabled(testing || serverURL.isEmpty)

                if testing {
                    ProgressView().controlSize(.small)
                }
                if let statusText {
                    Label(statusText, systemImage: succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(succeeded ? .green : .red)
                        .font(.caption)
                        .lineLimit(2)
                }
            }
        }
    }

    private func runTest() async {
        testing = true
        statusText = nil
        let outcome = await ServerProbe.checkVersion(baseURL: serverURL)
        testing = false
        switch outcome {
        case .success(let version):
            succeeded = true
            statusText = "Connected to Ollama \(version)."
        case .failure(let reason):
            succeeded = false
            statusText = reason
        }
        onVerified?(succeeded)
    }
}
