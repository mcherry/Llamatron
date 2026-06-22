import SwiftUI

/// Per-turn inspector: latency/token metrics, the retrieved context chunks with
/// relevance scores, and the exact request payload that produced the reply.
struct MessageInspectorView: View {
    let message: ChatMessage
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
                    metricsSection
                    if !message.retrievedChunks.isEmpty {
                        retrievalSection
                    }
                    if let payload = message.requestPayload {
                        requestSection(payload)
                    }
                }
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
        section("Request Payload", systemImage: "arrow.up.forward.square") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("The exact request sent for this turn.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Pasteboard.copy(payload)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(payload)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 240)
                .background(Color(nsColor: .textBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(nsColor: .separatorColor)))
            }
        }
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
