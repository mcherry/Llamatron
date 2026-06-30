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
