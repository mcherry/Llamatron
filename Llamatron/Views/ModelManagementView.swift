import SwiftUI
import LlamaEngine

/// Lists models on the Ollama server with their size and "loaded" state, lets the
/// user pull a new model (with progress) and delete existing ones. Read/write actions
/// go straight to the server via `OllamaClient`.
struct ModelManagementView: View {
    let serverURL: String

    @State private var models: [OllamaModel] = []
    @State private var running: Set<String> = []
    @State private var loading = false
    @State private var loadError: String?

    @State private var pullName = ""
    @State private var pulling = false
    @State private var pullStatus = ""
    @State private var pullFraction: Double?
    @State private var pullTask: Task<Void, Never>?

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
        .task { await reload() }
        .confirmationDialog("Delete this model?",
                            isPresented: deletePresented,
                            presenting: modelPendingDelete) { model in
            Button("Delete \(model.name)", role: .destructive) {
                Task { await delete(model) }
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
            if loading { ProgressView().controlSize(.small) }
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(loading)
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
                if pulling {
                    Button("Stop", role: .cancel) { pullTask?.cancel() }
                } else {
                    Button("Pull", action: startPull)
                        .disabled(pullName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if pulling || pullFraction != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let fraction = pullFraction {
                        ProgressView(value: fraction)
                    } else if pulling {
                        ProgressView()
                    }
                    Text(pullStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var modelList: some View {
        List {
            if models.isEmpty && !loading {
                Text("No models on the server.")
                    .foregroundStyle(.secondary)
            }
            ForEach(models) { model in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.name)
                        HStack(spacing: 6) {
                            if let size = model.sizeLabel {
                                Text(size)
                            }
                            if running.contains(model.name) {
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

    private func reload() async {
        guard let client = OllamaClient(baseURLString: serverURL) else {
            loadError = "Invalid server URL. Check Settings."
            return
        }
        loading = true
        loadError = nil
        do {
            models = try await client.models().sorted { $0.name < $1.name }
            running = Set((try? await client.runningModels())?.map(\.name) ?? [])
        } catch {
            loadError = error.localizedDescription
        }
        loading = false
    }

    private func startPull() {
        let name = pullName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let client = OllamaClient(baseURLString: serverURL) else { return }
        pulling = true
        pullStatus = "Starting…"
        pullFraction = nil
        loadError = nil
        pullTask = Task {
            do {
                for try await progress in client.pullModel(name) {
                    pullStatus = progress.status
                    pullFraction = progress.fraction
                }
                pullStatus = "Done"
            } catch is CancellationError {
                pullStatus = "Cancelled"
            } catch {
                loadError = error.localizedDescription
            }
            pulling = false
            pullFraction = nil
            await reload()
        }
    }

    private func delete(_ model: OllamaModel) async {
        guard let client = OllamaClient(baseURLString: serverURL) else { return }
        do {
            try await client.deleteModel(model.name)
            await reload()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
