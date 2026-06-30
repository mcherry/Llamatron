import AppKit

/// Thin wrapper over `NSPasteboard` for the per-message copy buttons.
enum Pasteboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Puts an image on the clipboard (e.g. a generated image reply).
    static func copy(image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}
