import SwiftUI
import LlamaEngine

/// Lists models on the Ollama server with their size and "loaded" state, lets the
/// user pull a new model (with progress) and delete existing ones. Read/write actions
/// go straight to the server via `OllamaClient`.
struct ModelManagementView: View {
    let serverURL: String

    @State private var manager = ModelManager()
    @State private var pullName = ""
    @State private var modelPendingDelete: OllamaModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            pullBar
            Divider()
            modelList
        }
        .padding()
        .frame(width: 520, height: 480)
        .task { await manager.reload(serverURL: serverURL) }
        .confirmationDialog("Delete this model?",
                            isPresented: deletePresented,
                            presenting: modelPendingDelete) { model in
            Button("Delete \(model.name)", role: .destructive) {
                Task { await manager.delete(model.name, serverURL: serverURL) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { model in
            Text("\(model.name) will be removed from the server\(model.sizeLabel.map { ", freeing \($0)" } ?? "").")
        }
    }

    private var header: some View {
        HStack {
            Text("Manage Models").font(.headline)
            Spacer()
            if manager.isLoading { ProgressView().controlSize(.small) }
            Button {
                Task { await manager.reload(serverURL: serverURL) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(manager.isLoading)
            .help("Refresh")
        }
    }

    private var pullBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Pull a model, e.g. llama3.2", text: $pullName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(startPull)
                if manager.isPulling {
                    Button("Stop", role: .cancel) { manager.cancelPull() }
                } else {
                    Button("Pull", action: startPull)
                        .disabled(pullName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if manager.isPulling || manager.pullFraction != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let fraction = manager.pullFraction {
                        ProgressView(value: fraction)
                    } else if manager.isPulling {
                        ProgressView()
                    }
                    Text(manager.pullStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let loadError = manager.errorMessage {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var modelList: some View {
        List {
            if manager.models.isEmpty && !manager.isLoading {
                Text("No models on the server.")
                    .foregroundStyle(.secondary)
            }
            ForEach(manager.models) { model in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name)
                        HStack(spacing: 6) {
                            if let size = model.sizeLabel {
                                Text(size)
                            }
                            if manager.isRunning(model.name) {
                                Label("Loaded", systemImage: "memorychip")
                                    .foregroundStyle(.green)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        modelPendingDelete = model
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete model")
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Actions

    private var deletePresented: Binding<Bool> {
        Binding(get: { modelPendingDelete != nil },
                set: { if !$0 { modelPendingDelete = nil } })
    }

    private func startPull() {
        manager.pull(pullName, serverURL: serverURL)
    }
}
