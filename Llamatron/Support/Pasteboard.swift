#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Thin cross-platform wrapper over the system clipboard for the per-message copy buttons.
enum Pasteboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    /// Puts an image on the clipboard (e.g. a generated image reply).
    static func copy(image: PlatformImage) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #else
        UIPasteboard.general.image = image
        #endif
    }
}
