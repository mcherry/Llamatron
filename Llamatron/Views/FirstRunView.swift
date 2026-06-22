import SwiftUI

/// Shown over the main window on first launch so the user points Llamatron at their
/// Ollama server before using it. "Get Started" stays disabled until a successful
/// connection test, and the sheet can't be dismissed until then.
struct FirstRunView: View {
    @AppStorage(SettingsKey.didCompleteFirstRun) private var didCompleteFirstRun = false
    @State private var verified = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Llamatron")
                .font(.title2).bold()
            Text("Point Llamatron at your Ollama server to get started. You can change this any time in Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ServerSettingsForm(onVerified: { verified = $0 })

            HStack {
                Spacer()
                Button("Get Started") {
                    didCompleteFirstRun = true
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!verified)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
