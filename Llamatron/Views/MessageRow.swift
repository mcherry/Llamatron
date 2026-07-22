import SwiftUI
import LlamaEngineStore
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers

/// One turn in the transcript. User turns are right-aligned and hug their content;
/// assistant turns are left-aligned and render Markdown. Each row has a caption with
/// the speaker and timestamp, plus a copy button on hover. Selectable text throughout.
struct MessageRow: View {
    let message: ChatMessage
    /// True only for the assistant reply that is currently streaming. While true the
    /// caption (timestamp + duration) is hidden, since the reply isn't finished yet.
    var isGenerating: Bool = false
    /// True when this message is currently being spoken (text-to-speech).
    var isSpeaking: Bool = false
    /// When set, a speaker button toggles reading this reply aloud.
    var onToggleSpeak: (() -> Void)?
    /// True while this reply's audio is being saved.
    var isSaving: Bool = false
    /// When set, a button saves this reply's audio to an `.m4a` file.
    var onSaveAudio: (() -> Void)?
    /// When set (image replies), the inspector offers a "Regenerate" action.
    var onRegenerate: (() -> Void)?
    /// When set, only the first N characters of the reply are shown — used to reveal a
    /// narrated reply in step with its audio. `nil` shows the whole reply.
    var revealedCharacters: Int?
    @State private var hovering = alwaysRevealControls
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
                if onToggleSpeak != nil {
                    speakButton
                }
                if onSaveAudio != nil {
                    saveAudioButton
                }
                if message.hasInspectorData {
                    inspectButton
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var speakButton: some View {
        Button {
            onToggleSpeak?()
        } label: {
            Image(systemName: isSpeaking ? "stop.circle" : "speaker.wave.2")
                .font(.caption2)
        }
        .buttonStyle(.borderless)
        .help(isSpeaking ? "Stop" : "Read aloud")
        .opacity(hovering || isSpeaking ? 1 : 0)
        .allowsHitTesting(hovering || isSpeaking)
    }

    @ViewBuilder
    private var saveAudioButton: some View {
        if isSaving {
            ProgressView().controlSize(.mini)
        } else {
            Button {
                onSaveAudio?()
            } label: {
                Image(systemName: "square.and.arrow.down")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Save audio (.m4a)")
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
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
            MessageInspectorView(message: message, onRegenerate: onRegenerate)
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
                if let data = message.generatedImageData, let nsImage = PlatformImage(data: data) {
                    generatedImage(nsImage)
                }
                if isHoldingForNarration {
                    narrationPlaceholder
                } else if !displayedContent.isEmpty {
                    MarkdownView(text: displayedContent, renderDiagrams: !isGenerating)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if isGenerating && message.thinking.isEmpty && message.generatedImageData == nil {
                    ProgressView()
                        .controlSize(.small)
                }
                toolImages
                if message.wasTruncated && !isGenerating {
                    truncationNotice
                }
            }
            .onAppear {
                // Auto-expand reasoning while it streams in; leave finished replies
                // collapsed so the transcript stays clean.
                thinkingExpanded = isGenerating && message.content.isEmpty
            }
            .onChange(of: message.content.isEmpty) { _, isEmpty in
                // The moment the reply itself starts arriving, the thinking pass is
                // finished — collapse it so the answer takes focus.
                if !isEmpty { thinkingExpanded = false }
            }
        }
    }

    /// The portion of the reply to display: the whole reply normally, or a growing
    /// prefix while a narration reveals it in step with the audio.
    private var displayedContent: String {
        guard let n = revealedCharacters else { return message.content }
        if n <= 0 { return "" }
        if n >= message.content.count { return message.content }
        return String(message.content.prefix(n))
    }

    /// True while a narrated reply is buffered, waiting for its audio to start.
    private var isHoldingForNarration: Bool {
        revealedCharacters == 0 && !message.content.isEmpty
    }

    /// Placeholder shown while a narrated reply waits for audio to begin.
    private var narrationPlaceholder: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform")
            Text("Preparing narration…")
            ProgressView().controlSize(.small)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
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

    /// A generated image reply with hover actions to save or copy it.
    /// Graphics produced by tools this turn (e.g. render_graphic), shown below the reply.
    @ViewBuilder
    private var toolImages: some View {
        let images = message.orderedToolCallRecords.compactMap { $0.imageData.flatMap { PlatformImage(data: $0) } }
        if !images.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 512, maxHeight: 512)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                }
            }
        }
    }

    private func generatedImage(_ nsImage: PlatformImage) -> some View {        VStack(alignment: .leading, spacing: 4) {
            Image(platformImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 512, maxHeight: 512)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 12) {
                Button { saveGeneratedImage() } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                Button { Pasteboard.copy(image: nsImage) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
    }

    /// Writes the generated PNG to a user-chosen location.
    private func saveGeneratedImage() {
        guard let data = message.generatedImageData else { return }
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = "image.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
        #else
        // iOS: write a temp PNG and offer it through the share sheet.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("image.png")
        if (try? data.write(to: url)) != nil {
            PlatformShare.present([url])
        }
        #endif
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
