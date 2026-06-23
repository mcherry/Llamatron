import SwiftUI
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
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if showingSource || failed {
                sourceBlock
            } else {
                MermaidWebView(source: source,
                               dark: colorScheme == .dark,
                               height: $height,
                               failed: $failed)
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

    private var header: some View {
        HStack {
            Text(failed ? "mermaid (couldn’t render)" : "mermaid")
                .font(.caption2)
                .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            Spacer()
            if !failed {
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

/// The sandboxed WebKit host that actually renders the diagram. Kept private to
/// `MermaidView`; all the security configuration lives here.
private struct MermaidWebView: NSViewRepresentable {
    let source: String
    let dark: Bool
    @Binding var height: CGFloat
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height, failed: $failed)
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

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Transparent so the SwiftUI card background shows through behind the diagram.
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(into: webView, source: source, dark: dark)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.reloadIfNeeded(webView, source: source, dark: dark)
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
        private var loadedKey: String?
        private var didInitialLoad = false

        init(height: Binding<CGFloat>, failed: Binding<Bool>) {
            self.height = height
            self.failed = failed
        }

        func reloadIfNeeded(_ webView: WKWebView, source: String, dark: Bool) {
            guard key(source, dark) != loadedKey else { return }
            load(into: webView, source: source, dark: dark)
        }

        func load(into webView: WKWebView, source: String, dark: Bool) {
            loadedKey = key(source, dark)
            didInitialLoad = false
            failed.wrappedValue = false
            webView.loadHTMLString(Self.html(source: source, dark: dark), baseURL: nil)
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
            case "failed":
                failed.wrappedValue = true
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
              function fail(e){ try{ window.webkit.messageHandlers.failed.postMessage(String(e)); }catch(_){ } }
              try{
                mermaid.initialize({ startOnLoad:false, securityLevel:'strict', theme:'\(theme)' });
                mermaid.parseError = function(err){ fail(err); };
                mermaid.render('graph', \(encoded), function(svg){
                  document.getElementById('c').innerHTML = svg;
                  requestAnimationFrame(function(){
                    var rect = document.getElementById('c').getBoundingClientRect();
                    try{ window.webkit.messageHandlers.sizing.postMessage(rect.height + 4); }catch(_){ }
                  });
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
