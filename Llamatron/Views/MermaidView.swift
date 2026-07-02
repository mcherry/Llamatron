import SwiftUI
import LlamaEngine
import WebKit

/// Renders a Mermaid diagram produced by a model. A "diagram" is just text the model
/// writes in Mermaid's syntax; the rendering is the client's job.
///
/// Security posture (diagram text is untrusted model output, possibly influenced by
/// injected content): the render runs in a locked-down `WKWebView` with a **locally
/// bundled** Mermaid (never a CDN), Mermaid's own `securityLevel: 'strict'` (no inline
/// HTML labels, no click handlers), a **no-network CSP** (`default-src 'none'`), and
/// **all navigation blocked** after the initial in-memory load. The diagram source is
/// JSON-encoded into the page so it can't break out of the script context, and a
/// "Source" toggle plus a parse-failure fallback keep the raw text inspectable.
struct MermaidView: View {
    let source: String

    @Environment(\.colorScheme) private var colorScheme
    @State private var showingSource = false
    @State private var height: CGFloat = 80
    @State private var failed = false
    @State private var errorText: String?
    @State private var autoCorrected = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if oversized || showingSource || failed {
                if failed, let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                } else if oversized {
                    Text("This diagram is unusually large (\(source.count) characters) and may be a runaway generation, so it isn’t rendered. The source is shown below.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                }
                sourceBlock
            } else {
                MermaidWebView(source: source,
                               repaired: MermaidSanitizer.repair(source),
                               dark: colorScheme == .dark,
                               height: $height,
                               failed: $failed,
                               errorText: $errorText,
                               autoCorrected: $autoCorrected)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .padding(8)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor))
        )
        .onHover { hovering = $0 }
    }

    private var headerLabel: String {
        if failed { return "mermaid · invalid diagram syntax" }
        if oversized { return "mermaid · too large to render" }
        if autoCorrected { return "mermaid · auto-corrected" }
        return "mermaid"
    }

    private var headerColor: AnyShapeStyle {
        if failed { return AnyShapeStyle(.red) }
        if oversized { return AnyShapeStyle(.orange) }
        if autoCorrected { return AnyShapeStyle(.orange) }
        return AnyShapeStyle(.secondary)
    }

    /// Guards against runaway model output: a pathologically large diagram is shown as
    /// source rather than handed to the web view, where it could render slowly or hang
    /// the UI. The threshold is far above any hand-authored diagram.
    private var oversized: Bool {
        source.count > 12_000
            || source.split(separator: "\n", omittingEmptySubsequences: false).count > 400
    }

    private var header: some View {
        HStack {
            Text(headerLabel)
                .font(.caption2)
                .foregroundStyle(headerColor)
                .help(autoCorrected ? "The model’s diagram had invalid syntax (unquoted labels); Llamatron quoted them to render it. Toggle Source to see the original." : "")
            Spacer()
            if !failed && !oversized {
                Button(showingSource ? "Diagram" : "Source") {
                    showingSource.toggle()
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
            Button {
                Pasteboard.copy(source)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy diagram source")
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary)
    }

    private var sourceBlock: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(source)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// A `WKWebView` that does not consume scroll-wheel events. The diagram is sized to fit
/// its content, so the web view never needs to scroll itself; forwarding the event to
/// the next responder lets the enclosing chat transcript scroll normally even when the
/// pointer is over a diagram.
private final class PassthroughScrollWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// The sandboxed WebKit host that actually renders the diagram. Kept private to
/// `MermaidView`; all the security configuration lives here.
private struct MermaidWebView: NSViewRepresentable {
    let source: String
    let repaired: String
    let dark: Bool
    @Binding var height: CGFloat
    @Binding var failed: Bool
    @Binding var errorText: String?
    @Binding var autoCorrected: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, failed: $failed,
                    errorText: $errorText, autoCorrected: $autoCorrected)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "sizing")
        controller.add(context.coordinator, name: "failed")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // No persistent cookies/cache; nothing should be stored.
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = PassthroughScrollWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Transparent so the SwiftUI card background shows through behind the diagram.
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        context.coordinator.load(source: source, repaired: repaired, dark: dark)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.webView = webView
        context.coordinator.reloadIfNeeded(source: source, repaired: repaired, dark: dark)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let height: Binding<CGFloat>
        private let failed: Binding<Bool>
        private let errorText: Binding<String?>
        private let autoCorrected: Binding<Bool>
        weak var webView: WKWebView?

        private var loadedKey: String?
        private var didInitialLoad = false

        // Dual-attempt state: render the model's original source first, and only fall
        // back to the auto-quoted version if the original fails to parse.
        private var rawSource = ""
        private var repairedSource = ""
        private var dark = false
        private var attemptedRepair = false
        private var renderingRepair = false
        private var firstError: String?

        init(height: Binding<CGFloat>, failed: Binding<Bool>,
             errorText: Binding<String?>, autoCorrected: Binding<Bool>) {
            self.height = height
            self.failed = failed
            self.errorText = errorText
            self.autoCorrected = autoCorrected
        }

        func reloadIfNeeded(source: String, repaired: String, dark: Bool) {
            guard key(source, dark) != loadedKey else { return }
            load(source: source, repaired: repaired, dark: dark)
        }

        func load(source: String, repaired: String, dark: Bool) {
            loadedKey = key(source, dark)
            rawSource = source
            repairedSource = repaired
            self.dark = dark
            attemptedRepair = false
            renderingRepair = false
            firstError = nil
            failed.wrappedValue = false
            errorText.wrappedValue = nil
            autoCorrected.wrappedValue = false
            render(rawSource)
        }

        private func render(_ src: String) {
            didInitialLoad = false
            webView?.loadHTMLString(Self.html(source: src, dark: dark), baseURL: nil)
        }

        private func key(_ source: String, _ dark: Bool) -> String { "\(dark)\n\(source)" }

        // Allow only the initial in-memory load; cancel any later navigation (link
        // clicks, redirects) a malicious diagram might attempt.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if didInitialLoad {
                decisionHandler(.cancel)
            } else {
                didInitialLoad = true
                decisionHandler(.allow)
            }
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            switch message.name {
            case "sizing":
                if let number = message.body as? NSNumber {
                    height.wrappedValue = min(max(CGFloat(number.doubleValue), 20), 4000)
                }
                if renderingRepair { autoCorrected.wrappedValue = true }
            case "failed":
                let text = (message.body as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // First failure: try the auto-quoted version if it differs.
                if !attemptedRepair, !repairedSource.isEmpty, repairedSource != rawSource {
                    attemptedRepair = true
                    renderingRepair = true
                    firstError = text
                    render(repairedSource)
                    return
                }
                failed.wrappedValue = true
                let shown = firstError ?? text
                if let shown, !shown.isEmpty { errorText.wrappedValue = shown }
            default:
                break
            }
        }

        /// The bundled Mermaid library, read once from the app bundle.
        private static let mermaidJS: String = {
            guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js"),
                  let js = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            return js
        }()

        private static func html(source: String, dark: Bool) -> String {
            let theme = dark ? "dark" : "default"
            let encoded = jsString(source)
            return """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data:; font-src data:;">
            <style>html,body{margin:0;padding:0;background:transparent;}#c{display:flex;justify-content:center;}svg{max-width:100%;height:auto;}</style>
            <script>\(mermaidJS)</script>
            </head><body><div id="c"></div>
            <script>
            (function(){
              function fail(e){
                var msg = (e && e.str) ? e.str : ((e && e.message) ? e.message : String(e));
                try{ window.webkit.messageHandlers.failed.postMessage(String(msg)); }catch(_){ }
              }
              try{
                mermaid.initialize({ startOnLoad:false, securityLevel:'strict', theme:'\(theme)' });
                mermaid.parseError = function(err){ fail(err); };
                mermaid.render('graph', \(encoded), function(svg){
                  var c = document.getElementById('c');
                  c.innerHTML = svg;
                  // Report the rendered height now and whenever it changes (e.g. the
                  // window resizes and the SVG, capped at max-width:100%, rescales), so
                  // the SwiftUI frame always matches the content and never clips it.
                  var last = -1;
                  function report(){
                    var h = c.getBoundingClientRect().height;
                    if (Math.abs(h - last) < 1) return;
                    last = h;
                    try{ window.webkit.messageHandlers.sizing.postMessage(h + 4); }catch(_){ }
                  }
                  if (window.ResizeObserver) { new ResizeObserver(report).observe(c); }
                  window.addEventListener('resize', report);
                  requestAnimationFrame(report);
                });
              }catch(e){ fail(e); }
            })();
            </script></body></html>
            """
        }

        /// Encodes a Swift string as a JS string literal (quoted + escaped) so the
        /// diagram text can't escape the script context it's embedded in.
        private static func jsString(_ value: String) -> String {
            if let data = try? JSONEncoder().encode(value),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return "\"\""
        }
    }
}
