import SwiftUI
import LlamaEngineStore
import LlamaEngine

/// Per-turn inspector: latency/token metrics, the retrieved context chunks with
/// relevance scores, and the exact request payload that produced the reply.
struct MessageInspectorView: View {
    let message: ChatMessage
    /// When set, a "Regenerate" action re-renders this image with a fresh seed.
    var onRegenerate: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Turn Inspector").font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let info = message.imageGenInfo {
                        imageSection(info)
                    }
                    metricsSection
                    if let vision = message.visionNote {
                        visionSection(vision)
                    }
                    if message.historyNote != nil || !message.historyRetrievedChunks.isEmpty {
                        historySection
                    }
                    if !message.retrievedChunks.isEmpty {
                        retrievalSection
                    }
                }
                .padding()
            }
            // Hug the metadata content so the payload below can fill the rest of the
            // panel instead of leaving a gap.
            .fixedSize(horizontal: false, vertical: true)

            if let payload = message.requestPayload {
                Divider()
                requestSection(payload)
                    .padding()
            }
        }
        .frame(width: 560, height: 620)
    }

    // MARK: - Metrics

    private var metricsSection: some View {
        section("Metrics", systemImage: "speedometer") {
            VStack(alignment: .leading, spacing: 4) {
                metricRow("Time to first token", message.firstTokenLabel)
                metricRow("Total time", message.generationDurationLabel)
                metricRow("Speed", message.tokensPerSecond.map { String(format: "%.1f tok/s", $0) })
                metricRow("Prompt tokens", message.promptTokens.map { $0.formatted() })
                metricRow("Response tokens", message.evalTokens.map { $0.formatted() })
            }
        }
    }

    private func metricRow(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .monospacedDigit()
        }
        .font(.callout)
    }

    // MARK: - Vision

    private func visionSection(_ note: String) -> some View {
        section("Vision", systemImage: "eye") {
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Image generation

    private func imageSection(_ info: ImageGenInfo) -> some View {
        section("Image", systemImage: "photo") {
            VStack(alignment: .leading, spacing: 8) {
                imageRow("Prompt", info.prompt)
                if !info.negativePrompt.isEmpty {
                    imageRow("Negative", info.negativePrompt)
                }
                metricRow("Model", info.model.isEmpty ? nil : info.model)
                metricRow("Size", info.sizeLabel)
                metricRow("Steps", "\(info.steps)")
                metricRow("CFG", String(format: "%.1f", info.cfgScale))
                metricRow("Seed", info.seed.map { "\($0)" } ?? "random")
                if let onRegenerate {
                    Button {
                        onRegenerate()
                        dismiss()
                    } label: {
                        Label("Regenerate (fresh seed)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    /// A label above a wrapping, selectable value — for long fields like the prompt.
    private func imageRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Conversation history

    private var historySection: some View {
        section("Conversation History", systemImage: "clock.arrow.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                if let note = message.historyNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !message.historyRetrievedChunks.isEmpty {
                    Text("Earlier turns pulled in, ranked by similarity to your message:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(message.historyRetrievedChunks.sorted { $0.score > $1.score }) { chunk in
                        chunkRow(chunk)
                    }
                }
            }
        }
    }

    // MARK: - Retrieval

    private var retrievalSection: some View {
        section("Retrieved Context", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(message.retrievedChunks.count) chunks used, ranked by similarity to the prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(message.retrievedChunks.sorted { $0.score > $1.score }) { chunk in
                    chunkRow(chunk)
                }
            }
        }
    }

    private func chunkRow(_ chunk: RetrievedChunkInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(chunk.sourceName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(String(format: "%.3f", chunk.score))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(max(0, min(1, chunk.score))))
                .progressViewStyle(.linear)
            Text(chunk.text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Request

    private func requestSection(_ payload: String) -> some View {
        // Not built on `section(...)`: this one fills the remaining panel height, so it
        // owns a flexible VStack instead of the content-hugging helper.
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Request Payload", systemImage: "arrow.up.forward.square")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    Pasteboard.copy(payload)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            Text("The exact request sent for this turn.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView([.vertical, .horizontal], showsIndicators: true) {
                Text(payload)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.platformTextBackground,
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.platformSeparator))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Helpers

    private func section<Content: View>(_ title: String,
                                        systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
