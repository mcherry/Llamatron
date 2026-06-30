import SwiftUI
import AppKit

/// One turn in the transcript. User turns are right-aligned and hug their content;
/// assistant turns are left-aligned and render Markdown. Each row has a caption with
/// the speaker and timestamp, plus a copy button on hover. Selectable text throughout.
struct MessageRow: View {
    let message: ChatMessage
    /// True only for the assistant reply that is currently streaming. While true the
    /// caption (timestamp + duration) is hidden, since the reply isn't finished yet.
    var isGenerating: Bool = false
    @State private var hovering = false
    @State private var thinkingExpanded = false
    @State private var showingInspector = false

    private var isUser: Bool { message.role == .user }
    private var showCopy: Bool { hovering && !message.content.isEmpty }
    /// Hide the caption only while this row's reply is still generating.
    private var showCaption: Bool { !isGenerating }

    /// Leaves a gap on the opposite side so the alignment reads clearly without the
    /// bubble ever spanning the full width.
    private let oppositeInset: CGFloat = 64

    /// Reasoning longer than this many characters streams inside a fixed-height,
    /// auto-scrolling box so a long "thinking" pass doesn't grow the row and scroll
    /// the whole transcript endlessly.
    private let thinkingScrollThreshold = 600
    private let thinkingBoxHeight: CGFloat = 200
    private let thinkingAnchor = "thinking-end"

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: oppositeInset) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                bubble
                if showCaption { caption }
            }

            if !isUser { Spacer(minLength: oppositeInset) }
        }
        // Make the whole row a single hover region. Without this, the transparent gap
        // between the bubble and the caption is a dead zone that fires a hover-exit,
        // so the copy button vanishes before the pointer can reach it.
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var bubble: some View {
        content
            .padding(12)
            .background(bubbleColor, in: RoundedRectangle(cornerRadius: 12))
    }

    private var caption: some View {
        HStack(spacing: 6) {
            if isUser { copyButton }
            Text(captionText)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !isUser {
                copyButton
                if message.hasInspectorData {
                    inspectButton
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var inspectButton: some View {
        Button {
            showingInspector = true
        } label: {
            Image(systemName: "wand.and.stars.inverse")
                .font(.caption2)
        }
        .buttonStyle(.borderless)
        .help("Inspect this turn")
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
        .sheet(isPresented: $showingInspector) {
            MessageInspectorView(message: message)
        }
    }

    private var copyButton: some View {
        Button {
            Pasteboard.copy(message.content)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.caption2)
        }
        .buttonStyle(.borderless)
        .help("Copy message")
        // Always present (just transparent off-hover) so showing it never shifts the
        // caption and makes the transcript jump.
        .opacity(showCopy ? 1 : 0)
        .allowsHitTesting(showCopy)
    }

    @ViewBuilder
    private var content: some View {
        if isUser {
            Text(message.content)
                .textSelection(.enabled)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if !message.thinking.isEmpty {
                    thinkingDisclosure
                }
                if let data = message.generatedImageData, let nsImage = NSImage(data: data) {
                    generatedImage(nsImage)
                }
                if !message.content.isEmpty {
                    MarkdownView(text: message.content, renderDiagrams: !isGenerating)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if message.thinking.isEmpty && message.generatedImageData == nil {
                    ProgressView()
                        .controlSize(.small)
                }
                if message.wasTruncated && !isGenerating {
                    truncationNotice
                }
            }
            .onAppear {
                // Auto-expand reasoning while it streams in; leave finished replies
                // collapsed so the transcript stays clean.
                thinkingExpanded = isGenerating && message.content.isEmpty
            }
        }
    }

    /// Shown when the model stopped because it hit the context window (`done_reason:
    /// length`) rather than finishing — the reply is incomplete.
    private var truncationNotice: some View {
        Label("Reply cut off — it reached the end of the context window. Increase the context size or use a smaller source.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.caption2)
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Collapsible reasoning trace from thinking models.
    private var thinkingDisclosure: some View {
        DisclosureGroup(isExpanded: $thinkingExpanded) {
            thinkingContent
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "brain")
                Text(isGenerating && message.content.isEmpty ? "Thinking…" : "Reasoning")
                if isGenerating && message.content.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Long reasoning streams inside a fixed-height, auto-scrolling box so the
    /// transcript doesn't scroll endlessly while the model thinks; short reasoning
    /// renders inline.
    @ViewBuilder
    private var thinkingContent: some View {
        if message.thinking.count > thinkingScrollThreshold {
            ScrollViewReader { proxy in
                ScrollView {
                    thinkingText
                    Color.clear.frame(height: 1).id(thinkingAnchor)
                }
                .frame(height: thinkingBoxHeight)
                .onChange(of: message.thinking) {
                    // Follow the latest reasoning only while it streams.
                    guard isGenerating else { return }
                    proxy.scrollTo(thinkingAnchor, anchor: .bottom)
                }
                .onAppear {
                    if isGenerating { proxy.scrollTo(thinkingAnchor, anchor: .bottom) }
                }
            }
            .padding(.top, 2)
        } else {
            thinkingText.padding(.top, 2)
        }
    }

    private var thinkingText: some View {
        Text(message.thinking)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A generated image reply, scaled to fit within the bubble.
    private func generatedImage(_ nsImage: NSImage) -> some View {
        Image(nsImage: nsImage)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 512, maxHeight: 512)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var captionText: String {
        if isUser {
            return "\(timestamp) · You"
        }
        var text = "Assistant · \(timestamp)"
        if let duration = message.generationDurationLabel {
            text += " (\(duration))"
        }
        return text
    }

    /// Short time for today's messages, with an abbreviated date for older ones.
    private var timestamp: String {
        let date = message.createdAt
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var bubbleColor: Color {
        isUser ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.10)
    }
}
