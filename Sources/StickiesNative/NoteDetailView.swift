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
    @Published var matches = 0
    @Published var current = 0

    private var query = ""

    func find(_ q: String) {
        query = q
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
        query = ""
        matches = 0
        current = 0
        view?.evaluateJavaScript("window.__snClear && window.__snClear()", in: nil, in: .defaultClient)
    }

    /// Re-apply after a document loads, so switching notes keeps the active query.
    func reapply() { if !query.isEmpty { find(query) } }

    private func jsString(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
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
    @ObservedObject var host: WebHost

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
        host.view = view
        context.coordinator.host = host
        view.loadHTMLString(document, baseURL: URL(string: Config.appBaseURL))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var host: WebHost
        init(host: WebHost) { self.host = host }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in host.reapply() }
        }
    }

    private var document: String {
        let body = isHTML ? Self.stripScripts(html) : "<pre class=\"plain\">\(escaped(html))</pre>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <!-- Blocks every script and network fetch the note carries. CSP does not
             apply to isolated content worlds, so the find highlighter still runs. -->
        <meta http-equiv="Content-Security-Policy"
              content="default-src 'none'; img-src data: https: http:; style-src 'unsafe-inline'; font-src data:">
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
          mark.sn-hit { background:#ffe066; color:#000; border-radius:2px; padding:0 1px; }
          mark.sn-hit.sn-cur { background:#ff9500; box-shadow:0 0 0 2px rgba(255,149,0,.45); }
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

    /// Secondary guard. The CSP above already stops a note's scripts from RUNNING;
    /// this stops their source text from sitting in the DOM, where it leaks into
    /// textContent, copy-paste and assistive tech.
    static func stripScripts(_ s: String) -> String {
        var out = s.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "", options: [.regularExpression, .caseInsensitive])
        out = out.replacingOccurrences(
            of: "<script[^>]*/?>", with: "", options: [.regularExpression, .caseInsensitive])
        for quote in ["\"", "'"] {
            out = out.replacingOccurrences(
                of: "\\son[a-zA-Z]+\\s*=\\s*\(quote)[^\(quote)]*\(quote)",
                with: "", options: [.regularExpression, .caseInsensitive])
        }
        return out
    }

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
                centered(ProgressView())
            }
        }
        .navigationTitle(note.title)
        .task(id: note.id) {
            content = nil; error = nil; host.clear()
            do {
                content = try await state.api.fetchNote(id: note.id).content ?? ""
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
    static let focusSearch = Notification.Name("focusSearch")
}
