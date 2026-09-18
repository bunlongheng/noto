import AppKit
import SwiftUI
import WebKit

/// Owns the live WKWebView so the toolbar find field can drive it.
///
/// WKWebView.find works but paints WebKit's native find overlay, which dims the
/// entire document and reveals one match at a time. This highlights EVERY match in
/// place instead, with the current one accented, and never dims the page.
@MainActor
final class WebHost: ObservableObject {
    weak var view: WKWebView?
    /// The toolbar's find field. Held so Cmd+F can put the caret in it: SwiftUI's
    /// @FocusState does not reach toolbar content, which is hosted in its own view
    /// tree, and a SwiftUI TextField there is not an NSTextField that can be found
    /// by walking the window either.
    weak var findField: NSSearchField?
    @Published var matches = 0
    @Published var current = 0
    /// Page zoom, kept here rather than on the web view so it survives switching
    /// notes - the web view is reused, but a fresh load would otherwise be the
    /// only thing carrying it.
    /// Restored from defaults, so a note opens at the size you last chose instead
    /// of at whatever each note's own HTML asks for.
    @Published private(set) var zoom: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "pageZoom")
        return saved > 0 ? CGFloat(saved) : 1
    }()
    /// True while the zoom badge is on screen. Zooming is otherwise silent past
    /// the first notch - the page reflows, but nothing says how far you have gone
    /// or how to get back.
    @Published private(set) var showingZoom = false
    private var zoomFade: Task<Void, Never>?

    func zoomBy(_ delta: CGFloat) {
        zoom = min(3, max(0.5, zoom + delta))
        view?.pageZoom = zoom
        UserDefaults.standard.set(Double(zoom), forKey: "pageZoom")
        flashZoom()
    }

    func resetZoom() {
        zoom = 1
        view?.pageZoom = 1
        UserDefaults.standard.set(1.0, forKey: "pageZoom")
        flashZoom()
    }

    /// Show the badge and restart the fade. Restarting matters: holding Cmd+= is a
    /// run of separate calls, and a timer left from the first would hide the badge
    /// mid-zoom.
    private func flashZoom() {
        showingZoom = true
        zoomFade?.cancel()
        zoomFade = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            self?.showingZoom = false
        }
    }

    func find(_ q: String) {
        guard let view else { return }
        let js = "window.__snFind(\(jsString(q)))"
        view.evaluateJavaScript(js, in: nil, in: .defaultClient) { [weak self] result in
            let result = try? result.get()
            Task { @MainActor in
                let n = (result as? Int) ?? 0
                self?.matches = n
                self?.current = n > 0 ? 1 : 0
            }
        }
    }

    func step(_ forward: Bool) {
        guard let view, matches > 0 else { return }
        view.evaluateJavaScript("window.__snStep(\(forward ? 1 : -1))", in: nil, in: .defaultClient) { [weak self] result in
            let value = try? result.get()
            Task { @MainActor in self?.current = (value as? Int) ?? 0 }
        }
    }

    func clear() {
        matches = 0
        current = 0
        view?.evaluateJavaScript("window.__snClear && window.__snClear()", in: nil, in: .defaultClient)
    }

    /// Put the caret in the find field. False when there is no field to focus,
    /// so the caller can leave the key to whatever else wants it.
    @discardableResult
    func focusFind() -> Bool {
        guard let findField, let window = findField.window else { return false }
        return window.makeFirstResponder(findField)
    }

    /// A JSON string literal is also a valid JavaScript string literal, and unlike
    /// hand-rolled escaping it cannot miss a control character.
    private func jsString(_ s: String) -> String {
        (try? JSONEncoder().encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}

/// A real NSSearchField for the toolbar.
///
/// SwiftUI's TextField cannot be focused programmatically from a toolbar item, so
/// the one control the app needs to drive from a keyboard shortcut is built in
/// AppKit, where making it first responder is a single call.
struct FindField: NSViewRepresentable {
    @Binding var text: String
    let host: WebHost
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Find in note"
        field.font = .systemFont(ofSize: 12)
        field.delegate = context.coordinator
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        host.findField = field
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        // Only when it actually differs - assigning while the user types would
        // reset the insertion point to the end on every keystroke.
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        private let parent: FindField
        init(_ parent: FindField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

/// Read-only renderer.
///
/// Note scripts are stripped from the markup before loading rather than disabling
/// JavaScript wholesale - the viewer still must not execute what a note carries, but
/// the find highlighter needs to run.
struct HTMLView: NSViewRepresentable {
    let html: String
    let isHTML: Bool
    /// Deliberately NOT @ObservedObject. This view never reads WebHost's published
    /// values, and observing them made every find keystroke invalidate the
    /// representable, which re-ran loadHTMLString below - a reload loop that wiped
    /// the highlights it had just drawn.
    let host: WebHost

    func makeCoordinator() -> Coordinator { Coordinator(host: host) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // The highlighter lives in an ISOLATED content world, so the CSP below can
        // block every script the note carries without disabling our own.
        config.userContentController.addUserScript(
            WKUserScript(source: Self.finder,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true,
                         in: .defaultClient)
        )
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        host.view = view
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        // Load ONLY when the document actually changed. updateNSView runs on every
        // SwiftUI invalidation; reloading unconditionally restarts the page and
        // throws away find state.
        let doc = document
        guard context.coordinator.loadedDocument != doc else { return }
        context.coordinator.loadedDocument = doc
        view.pageZoom = host.zoom
        view.loadHTMLString(doc, baseURL: URL(string: Config.appBaseURL))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let host: WebHost
        var loadedDocument: String?
        init(host: WebHost) { self.host = host }

        /// A note is a document to read, not a browser. Only the initial
        /// loadHTMLString is allowed in place; a link opens in the default browser
        /// instead of replacing the note with a remote page where the CSP no
        /// longer applies and scripts run freely.
        @MainActor
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            // .other used to be allowed outright, which was safe while notes could not
            // run code. Now that they can, a note script could set location.href and
            // sail the web view to a remote page - where OUR meta CSP no longer
            // applies and its scripts would run unrestricted. Only the initial
            // in-place load is allowed through.
            if navigationAction.navigationType == .other {
                let url = navigationAction.request.url
                let isInitialLoad = url == nil
                    || url?.scheme == "about"
                    || url?.absoluteString.hasPrefix(Config.appBaseURL) == true
                if isInitialLoad { return .allow }
            }
            if let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }
    }

    private var document: String {
        let body = isHTML ? html : "<pre class=\"plain\">\(escaped(html))</pre>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <!-- A note may DRAW but may not PHONE HOME.
             Reports written by the /html skill chart with Chart.js from a CDN and an
             inline script, and with scripts blocked outright those canvases rendered
             as empty boxes here while the web app showed them. So scripts run, and
             the two CDNs those reports use may serve them - but connect-src 'none'
             kills fetch/XHR/WebSocket, form-action 'none' kills submissions, and
             everything not named here is still denied. A note can render itself; it
             cannot ship what it read anywhere. -->
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://cdnjs.cloudflare.com https://cdn.jsdelivr.net; style-src 'unsafe-inline'; img-src data: https: http:; font-src data: https:; connect-src 'none'; form-action 'none'; base-uri 'none'; object-src 'none'">
        <style>
          /* Notes are authored light-theme only (the /html skill enforces it) and set
             colours on their own elements. Declaring "light dark" let macOS dark mode
             turn the INHERITED text colour white, so every paragraph the note did not
             colour itself vanished against its own white cards. Pin it light and state
             the ink explicitly - this is what the web app renders. */
          :root { color-scheme: light; }
          html { background:#ffffff; }
          body { margin:0; padding:18px; background:#ffffff; color:#1c1c1e;
                 font:14px/1.55 -apple-system,BlinkMacSystemFont,system-ui,sans-serif; }
          img, table { max-width:100%; }
          pre { overflow-x:auto; }
          pre.plain { white-space:pre-wrap; word-wrap:break-word; font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; }
          /* Every match wears the SAME yellow - two fills (yellow for the rest,
             orange for the current one) read as two kinds of hit rather than one
             set. The current match is marked by an outline instead, so it still
             stands out without changing colour. */
          mark.sn-hit { background:#ffe066; color:#000; border-radius:2px; padding:0 1px; }
          mark.sn-hit.sn-cur { box-shadow:0 0 0 2px #1c1c1e; }
        </style></head><body>\(body)</body></html>
        """
    }

    /// Wraps every match in a <mark>, tracks the current one, scrolls it into view.
    static let finder: String = {
        """
        (function(){
          var hits = [], cur = -1;
          function unwrap(){
            document.querySelectorAll('mark.sn-hit').forEach(function(m){
              var t = document.createTextNode(m.textContent);
              m.parentNode.replaceChild(t, m);
            });
            document.body.normalize();
            hits = []; cur = -1;
          }
          window.__snClear = unwrap;
          window.__snFind = function(q){
            unwrap();
            if(!q) return 0;
            var needle = q.toLowerCase();
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
              acceptNode: function(n){
                if(!n.nodeValue || !n.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
                var p = n.parentNode.nodeName;
                if(p === 'SCRIPT' || p === 'STYLE') return NodeFilter.FILTER_REJECT;
                return n.nodeValue.toLowerCase().indexOf(needle) === -1
                  ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
              }
            });
            var targets = [], n;
            while((n = walker.nextNode())) targets.push(n);
            targets.forEach(function(node){
              var text = node.nodeValue, low = text.toLowerCase();
              var frag = document.createDocumentFragment(), i = 0, at;
              while((at = low.indexOf(needle, i)) !== -1){
                if(at > i) frag.appendChild(document.createTextNode(text.slice(i, at)));
                var m = document.createElement('mark');
                m.className = 'sn-hit';
                m.textContent = text.substr(at, q.length);
                frag.appendChild(m);
                i = at + q.length;
              }
              if(i < text.length) frag.appendChild(document.createTextNode(text.slice(i)));
              node.parentNode.replaceChild(frag, node);
            });
            hits = Array.prototype.slice.call(document.querySelectorAll('mark.sn-hit'));
            if(hits.length){ cur = 0; focus(); }
            return hits.length;
          };
          window.__snStep = function(dir){
            if(!hits.length) return 0;
            cur = (cur + dir + hits.length) % hits.length;
            focus();
            return cur + 1;
          };
          function focus(){
            hits.forEach(function(h){ h.classList.remove('sn-cur'); });
            var h = hits[cur];
            if(h){ h.classList.add('sn-cur'); h.scrollIntoView({block:'center'}); }
          }
        })();
        """
    }()

    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct NoteDetailView: View {
    let note: Note
    @ObservedObject var host: WebHost
    @EnvironmentObject var state: AppState
    @State private var content: String?
    @State private var error: String?

    var body: some View {
        Group {
            if let error {
                centered(Text(error).foregroundStyle(.secondary))
            } else if let content {
                HTMLView(html: content, isHTML: (note.type ?? "") == "html", host: host)
            } else {
                centered(LaunchTile(note: note))
            }
        }
        .navigationTitle(note.title)
        .task(id: note.id) {
            content = nil; error = nil; host.clear()
            do {
                content = try await state.body(for: note)
            } catch is CancellationError {
                // Selection moved on - a superseded load is not an error to show.
            } catch let urlError as URLError where urlError.code == .cancelled {
                // Same, surfaced by URLSession instead of the task.
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func centered<V: View>(_ v: V) -> some View {
        VStack { Spacer(); v; Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let focusFind = Notification.Name("focusFind")
}
