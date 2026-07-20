import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A multiline text input that sends on Return and inserts a newline on
/// Shift+Return. SwiftUI's `TextEditor` can't intercept Return reliably, so this
/// wraps `NSTextView` (macOS) / `UITextView` (iOS) and scrolls internally when its
/// content exceeds the frame.
#if os(macOS)
struct ChatInputTextView: NSViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSend: onSend)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 5, height: 7)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSend = onSend
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        var onSend: () -> Void

        init(text: Binding<String>, onSend: @escaping () -> Void) {
            self.text = text
            self.onSend = onSend
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        /// Return sends; Shift+Return inserts a newline. While an IME composition is
        /// active, Return is left to the input method.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            if textView.hasMarkedText() { return false }
            let shiftHeld = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if shiftHeld { return false }
            onSend()
            return true
        }
    }
}
#else

// MARK: - iOS

struct ChatInputTextView: UIViewRepresentable {
    @Binding var text: String
    var onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSend: onSend)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = SendingTextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = true
        textView.textContainerInset = UIEdgeInsets(top: 7, left: 3, bottom: 7, right: 3)
        textView.text = text
        // Shift+Return (hardware keyboard) inserts a newline; plain Return sends.
        textView.onShiftReturn = { [weak textView] in textView?.insertText("\n") }
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onSend = onSend
        if textView.text != text {
            textView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>
        var onSend: () -> Void

        init(text: Binding<String>, onSend: @escaping () -> Void) {
            self.text = text
            self.onSend = onSend
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        /// Plain Return sends. Shift+Return is intercepted by the view's key command and
        /// never reaches here, so it inserts a newline instead.
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard replacement == "\n" else { return true }
            onSend()
            return false
        }
    }
}

/// A `UITextView` that maps Shift+Return on a hardware keyboard to a newline (plain
/// Return is left to the delegate, which sends).
private final class SendingTextView: UITextView {
    var onShiftReturn: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: "\r", modifierFlags: .shift, action: #selector(handleShiftReturn))]
    }

    @objc private func handleShiftReturn() {
        onShiftReturn?()
    }
}
#endif
