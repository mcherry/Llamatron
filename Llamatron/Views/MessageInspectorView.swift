import SwiftUI
import LlamaEngineStore
import LlamaEngine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

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
                    if !message.orderedToolCallRecords.isEmpty {
                        toolCallsSection
                    }
                }
                .padding()
            }

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
                if let timings = message.timings {
                    metricRow("Prompt processing", prefillLabel(timings))
                    metricRow("Prompt cache", cacheLabel(timings))
                }
                if message.toolRounds > 0 {
                    metricRow("Tool rounds", "\(message.toolRounds)")
                }
            }
        }
    }

    /// The server's own prefill numbers, e.g. "1.2s · 850 tok/s".
    private func prefillLabel(_ timings: TurnTimings) -> String? {
        let parts = [
            timings.promptMilliseconds.map { $0 < 1000 ? "\(Int($0)) ms" : String(format: "%.1fs", $0 / 1000) },
            timings.promptTokensPerSecond.map { String(format: "%.0f tok/s", $0) }
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// e.g. "3,900 of 4,100 tokens reused (95%)".
    private func cacheLabel(_ timings: TurnTimings) -> String? {
        guard let cached = timings.cachedTokens, let total = timings.totalPromptTokens,
              let rate = timings.cacheHitRate else { return nil }
        return "\(cached.formatted()) of \(total.formatted()) tokens reused (\(Int((rate * 100).rounded()))%)"
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

    // MARK: - Tools

    private var toolCallsSection: some View {
        section("Tool Calls", systemImage: "wrench.and.screwdriver") {
            let records = message.orderedToolCallRecords
            VStack(alignment: .leading, spacing: 10) {
                Text("\(records.count) tool call\(records.count == 1 ? "" : "s") the model made this turn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if message.recoveredToolCalls > 0 {
                    let count = message.recoveredToolCalls
                    Label("\(count) call\(count == 1 ? " was" : "s were") written as text and recovered — the server's chat template didn't convert \(count == 1 ? "it" : "them") into a tool call.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                ForEach(records) { record in
                    toolRecordRow(record)
                }
            }
        }
    }

    private func toolRecordRow(_ record: ToolCallRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.toolName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                decisionBadge(record.decision)
                Spacer()
                if let seconds = record.durationSeconds {
                    Text(String(format: "%.2fs", seconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !record.arguments.isEmpty && record.arguments != "{}" {
                Text(record.arguments)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Text(record.result)
                .font(.caption)
                .foregroundStyle(record.isError ? Color.orange : Color.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
            if let data = record.imageData, let image = PlatformImage(data: data) {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func decisionBadge(_ decision: String) -> some View {
        let style = decisionStyle(decision)
        Text(style.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(style.color.opacity(0.18), in: Capsule())
            .foregroundStyle(style.color)
    }

    private func decisionStyle(_ decision: String) -> (label: String, color: Color) {
        switch decision {
        case "auto":      return ("auto-run", .green)
        case "confirmed": return ("confirmed", .blue)
        case "approved":  return ("approved", .blue)
        case "denied":    return ("denied", .red)
        case "invalid":   return ("invalid args", .orange)
        case "unknown":   return ("unknown tool", .orange)
        default:          return (decision, .gray)
        }
    }

    private var retrievalSection: some View {
        section("Retrieved Context", systemImage: "doc.text.magnifyingglass") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(message.retrievedChunks.count) chunks used, ranked by relevance to the prompt (keywords and meaning).")
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
            PayloadText(text: payload)
                .background(Color.platformTextBackground,
                            in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.platformSeparator))
                // The floor matters: this section is fully flexible and a scroll view
                // accepts a zero height silently, so without it a metadata-heavy turn
                // (tool calls + retrieval) squeezes the payload out of the panel entirely.
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
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

/// Read-only, selectable monospaced text that scrolls and wraps. A single SwiftUI `Text` this
/// large draws nothing once it outgrows the GPU's texture limit; TextKit draws only what's visible.
private struct PayloadText: PlatformViewRepresentable {
    let text: String

    #if os(macOS)
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 4, height: 8)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        let font = NSFont.monospacedSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .caption1).pointSize,
                                               weight: .regular)
        textView.textStorage?.setAttributedString(
            NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor]))
    }
    #else
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.text != text else { return }
        let font = UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
                                               weight: .regular)
        textView.attributedText = NSAttributedString(string: text,
                                                     attributes: [.font: font, .foregroundColor: UIColor.label])
    }
    #endif
}
