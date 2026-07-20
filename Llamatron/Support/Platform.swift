import SwiftUI
#if os(macOS)
import AppKit
/// The platform's bitmap image type: `NSImage` on macOS, `UIImage` on iOS.
typealias PlatformImage = NSImage
/// The platform's SwiftUI view-representable protocol.
typealias PlatformViewRepresentable = NSViewRepresentable
#else
import UIKit
typealias PlatformImage = UIImage
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// On touch platforms there's no pointer hover, so controls that reveal on hover (copy,
/// inspect, save, delete) start visible instead of staying hidden. On macOS this is
/// `false`, so hover behavior is exactly as it was.
#if os(macOS)
let alwaysRevealControls = false
#else
let alwaysRevealControls = true
#endif

extension Image {
    /// Cross-platform image initializer so call sites don't branch on `NSImage`/`UIImage`.
    init(platformImage: PlatformImage) {        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

extension Color {
    /// The system text-area background. `NSColor.textBackgroundColor` on macOS (unchanged
    /// from before); the closest UIKit equivalent on iOS.
    static var platformTextBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    /// The system separator/hairline color.
    static var platformSeparator: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(uiColor: .separator)
        #endif
    }

    // Code-syntax colors. The `system*` variants exist on both AppKit and UIKit, so macOS
    // keeps the exact same NSColor it used before.
    static var codeKeyword: Color {
        #if os(macOS)
        Color(nsColor: .systemPurple)
        #else
        Color(uiColor: .systemPurple)
        #endif
    }

    static var codeString: Color {
        #if os(macOS)
        Color(nsColor: .systemRed)
        #else
        Color(uiColor: .systemRed)
        #endif
    }

    static var codeComment: Color {
        #if os(macOS)
        Color(nsColor: .systemGreen)
        #else
        Color(uiColor: .systemGreen)
        #endif
    }

    static var codeNumber: Color {
        #if os(macOS)
        Color(nsColor: .systemBlue)
        #else
        Color(uiColor: .systemBlue)
        #endif
    }
}

/// An "i" info affordance: a hover tooltip on macOS (unchanged), and a tap-to-show
/// popover on iOS/iPad, where there is no pointer hover.
struct InfoButton: View {
    let text: String
    #if os(iOS)
    @State private var showing = false
    #endif

    var body: some View {
        #if os(macOS)
        Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .help(text)
        #else
        Button { showing = true } label: {
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .popover(isPresented: $showing) {
            Text(text)
                .font(.callout)
                .padding()
                .frame(maxWidth: 320)
                .presentationCompactAdaptation(.popover)
        }
        #endif
    }
}

#if os(iOS)
import UIKit
import UniformTypeIdentifiers

/// Presents a share sheet for the given items from the active window — the iOS stand-in
/// for the macOS save panels used to export images and audio.
enum PlatformShare {
    @MainActor
    static func present(_ items: [Any]) {
        guard let root = Self.topViewController() else { return }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // iPad requires a popover anchor.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = root.view
            popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        root.present(controller, animated: true)
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}

/// Opens a file via the iOS document picker — the stand-in for `NSOpenPanel`.
enum PlatformOpen {
    @MainActor
    static func pick(_ types: [UTType], onPick: @escaping (URL?) -> Void) {
        guard let top = PlatformShare.topViewController() else { onPick(nil); return }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.allowsMultipleSelection = false
        let delegate = DocumentPickerDelegate(onPick: onPick)
        picker.delegate = delegate
        top.present(picker, animated: true)
    }
}

/// Retains itself until the picker calls back, then releases.
private final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let onPick: (URL?) -> Void
    private var selfRef: DocumentPickerDelegate?

    init(onPick: @escaping (URL?) -> Void) {
        self.onPick = onPick
        super.init()
        selfRef = self
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }

    private func finish(_ url: URL?) {
        onPick(url)
        selfRef = nil
    }
}
#endif
