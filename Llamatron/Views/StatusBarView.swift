import SwiftUI
import LlamaEngine

/// Thin stats strip along the bottom of the chat. Shows turn count, how full the
/// context is (last prompt size vs the session limit), running token totals, and
/// the most recent reply's generation speed. While a reply streams it shows a live
/// "Generating…" indicator instead of the speed.
struct StatusBarView: View {
    let session: ChatSession
    let isStreaming: Bool

    private var messages: [ChatMessage] {
        session.orderedMessages.filter { $0.role != .system }
    }

    private var lastAssistant: ChatMessage? {
        messages.last { $0.role == .assistant }
    }

    private var totalPromptTokens: Int {
        messages.compactMap(\.promptTokens).reduce(0, +)
    }

    private var totalEvalTokens: Int {
        messages.compactMap(\.evalTokens).reduce(0, +)
    }

    var body: some View {
        HStack(spacing: 10) {
            stat("bubble.left.and.bubble.right", "\(messages.count)",
                 help: "Messages in this session")

            if let prompt = lastAssistant?.promptTokens {
                divider
                stat("gauge.with.dots.needle.67percent",
                     "\(prompt.formatted()) / \(ContextSize.label(session.contextSize))",
                     help: "Last prompt size vs. the session context window")
            }

            Spacer()

            if totalPromptTokens > 0 || totalEvalTokens > 0 {
                stat("arrow.up", totalPromptTokens.formatted(), help: "Total prompt tokens sent")
                stat("arrow.down", totalEvalTokens.formatted(), help: "Total tokens generated")
                divider
            }

            if isStreaming {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Generating…")
                }
            } else if let speed = lastAssistant?.tokensPerSecond {
                stat("speedometer", String(format: "%.1f tok/s", speed),
                     help: "Generation speed of the last reply")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(.bar)
    }

    private func stat(_ systemImage: String, _ text: String, help: String) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .help(help)
            .monospacedDigit()
    }

    private var divider: some View {
        Divider().frame(height: 12)
    }
}
