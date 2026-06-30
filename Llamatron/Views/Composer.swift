import SwiftUI
import AppKit

/// Multiline input with an embedded send/stop button in the bottom-right corner and
/// a draggable top edge to resize its height (persisted across launches). Return
/// sends; Shift+Return inserts a newline. Cmd-Return also sends and Cmd-. stops.
struct Composer: View {
    @Binding var text: String
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    var onAttach: (() -> Void)?
    var onAddWebSource: (() -> Void)?
    var onWebSearch: (() -> Void)?
    /// When set, a mic button toggles speech-to-text dictation into the field.
    var onMic: (() -> Void)?
    /// True while dictation is actively transcribing, for the mic button's state.
    var isDictating: Bool = false
    /// True when dictation previously failed (e.g. Dictation is off); the mic shows a
    /// disabled look and explains on click instead of trying again.
    var dictationUnavailable: Bool = false
    /// When set, a button toggles always-on, hands-free conversation mode.
    var onConversation: (() -> Void)?
    /// True while conversation mode is active, for the button's state.
    var conversationActive: Bool = false

    @AppStorage(SettingsKey.composerHeight) private var storedHeight = SettingsDefault.composerHeight
    /// Live height while a resize drag is in progress; `nil` when not dragging.
    /// Driving the drag from transient state (and only writing `storedHeight` on
    /// release) keeps it smooth and avoids a UserDefaults write every frame.
    @State private var liveHeight: Double?
    @State private var dragStartHeight: Double?

    private let minHeight: Double = 44
    private let maxHeight: Double = 400

    private var height: CGFloat {
        CGFloat(min(max(liveHeight ?? storedHeight, minHeight), maxHeight))
    }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            inputArea
                .padding(.horizontal)
                .padding(.bottom)
                .padding(.top, 2)
        }
    }

    // MARK: - Resize handle

    private var resizeHandle: some View {
        ZStack {
            Divider()
            Capsule()
                .fill(.secondary)
                .frame(width: 36, height: 5)
                .opacity(0.4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 12)
        .contentShape(Rectangle())
        .onHover { inside in
            // `.set()` (not push/pop) so repeated hover callbacks during a resize
            // can't imbalance the cursor stack and make it flicker.
            if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            // Measure in global space: the handle moves as the composer resizes, so
            // a local translation would chase its own frame and jitter.
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    let base = dragStartHeight ?? storedHeight
                    if dragStartHeight == nil { dragStartHeight = base }
                    // Dragging up (negative translation) grows the input.
                    liveHeight = clamp(base - value.translation.height)
                }
                .onEnded { value in
                    let base = dragStartHeight ?? storedHeight
                    storedHeight = clamp(base - value.translation.height)
                    liveHeight = nil
                    dragStartHeight = nil
                }
        )
        .help("Drag to resize")
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, minHeight), maxHeight)
    }

    // MARK: - Input + embedded buttons

    private var inputArea: some View {
        ZStack(alignment: .bottom) {
            ChatInputTextView(text: $text) {
                if canSend { onSend() }
            }
            .frame(height: height)
            .padding(.vertical, 6)
            // Reserve space so text never flows under the corner buttons.
            .padding(.horizontal, 40)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            HStack(alignment: .bottom) {
                if onAttach != nil {
                    attachButton
                }
                if onAddWebSource != nil || onWebSearch != nil {
                    webButton
                }
                if onMic != nil {
                    micButton
                }
                if onConversation != nil {
                    conversationButton
                }
                Spacer()
                sendStopButton
            }
            .padding(8)
        }
    }

    private var attachButton: some View {
        Button {
            onAttach?()
        } label: {
            Image(systemName: "paperclip")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Attach a file for context")
    }

    private var webButton: some View {
        Menu {
            if let onAddWebSource {
                Button {
                    onAddWebSource()
                } label: {
                    Label("Add Web Page or Text…", systemImage: "doc.text.magnifyingglass")
                }
            }
            if let onWebSearch {
                Button {
                    onWebSearch()
                } label: {
                    Label("Search the Web…", systemImage: "magnifyingglass")
                }
            }
        } label: {
            Image(systemName: "globe")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add web content for context")
    }

    private var micButton: some View {
        Button {
            onMic?()
        } label: {
            Image(systemName: micSymbol)
                .font(.title3)
                .foregroundStyle(micColor)
                .symbolEffect(.pulse, isActive: isDictating)
        }
        .buttonStyle(.plain)
        .help(micHelp)
    }

    private var micSymbol: String {
        if isDictating { return "mic.fill" }
        if dictationUnavailable { return "mic.slash" }
        return "mic"
    }

    private var micColor: Color {
        if isDictating { return .red }
        if dictationUnavailable { return .orange }
        return .secondary
    }

    private var micHelp: String {
        if isDictating { return "Stop dictation" }
        if dictationUnavailable { return "Speech-to-text needs Dictation on — click for details" }
        return "Dictate a message"
    }

    private var conversationButton: some View {
        Button {
            onConversation?()
        } label: {
            Image(systemName: conversationActive ? "ear.fill" : "ear")
                .font(.title3)
                .foregroundStyle(conversationActive ? Color.accentColor : .secondary)
                .symbolEffect(.pulse, isActive: conversationActive)
        }
        .buttonStyle(.plain)
        .help(conversationActive ? "Stop conversation mode" : "Conversation mode — always-on, hands-free")
    }

    @ViewBuilder
    private var sendStopButton: some View {
        if isStreaming {
            Button(action: onStop) {
                Image(systemName: "stop.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(".", modifiers: .command)
            .help("Stop generating")
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!canSend)
            .help("Send  ·  Return")
        }
    }
}
