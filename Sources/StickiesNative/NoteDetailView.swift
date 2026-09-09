import SwiftUI
import WebKit

/// Owns the live WKWebView so the find bar can drive it. WKWebView.find highlights
/// matches natively, so both html and plain-text notes get real in-page search as
/// long as everything renders through the web view.
@MainActor
final class WebHost: ObservableObject {
    weak var view: WKWebView?
    @Published var noMatch = false

    func find(_ query: String, forward: Bool = true) {
        guard let view, !query.isEmpty else { noMatch = false; return }
        let config = WKFindConfiguration()
        config.backwards = !forward
        config.wraps = true
        config.caseSensitive = false
        view.find(query, configuration: config) { [weak self] result in
            Task { @MainActor in self?.noMatch = !result.matchFound }
        }
    }

    func clear() {
        noMatch = false
        view?.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }
}

/// Read-only renderer. JavaScript is off: these notes are self-contained markup and
/// a viewer has no reason to execute anything they carry.
struct HTMLView: NSViewRepresentable {
    let html: String
    let isHTML: Bool
    @ObservedObject var host: WebHost

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        host.view = view
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        host.view = view
        view.loadHTMLString(document, baseURL: URL(string: Config.appBaseURL))
    }

    /// Notes are body fragments. Plain text goes through the same web view inside a
    /// <pre> so one find implementation covers every note type.
    private var document: String {
        let body = isHTML ? html : "<pre class=\"plain\">\(escaped(html))</pre>"
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body { margin:0; padding:18px; font:14px/1.55 -apple-system,BlinkMacSystemFont,system-ui,sans-serif; }
          img, table { max-width:100%; }
          pre { overflow-x:auto; }
          pre.plain { white-space:pre-wrap; word-wrap:break-word; font:13px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace; }
        </style></head><body>\(body)</body></html>
        """
    }

    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct NoteDetailView: View {
    let note: Note
    @EnvironmentObject var state: AppState
    @StateObject private var host = WebHost()
    @State private var content: String?
    @State private var error: String?
    @State private var find = ""
    @FocusState private var findFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            findBar
            Divider()
            Group {
                if let error {
                    centered(Text(error).foregroundStyle(.secondary))
                } else if let content {
                    HTMLView(html: content, isHTML: (note.type ?? "") == "html", host: host)
                } else {
                    centered(ProgressView())
                }
            }
        }
        .navigationTitle(note.title)
        .task(id: note.id) {
            content = nil; error = nil; find = ""; host.clear()
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
        .onExitCommand { find = ""; host.clear() }
    }

    /// Find-in-note. Cmd-F focuses it; Return and Shift-Return step through matches.
    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Find in note", text: $find)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($findFocused)
                .onSubmit { host.find(find, forward: true) }
                .onChange(of: find) { _, new in host.find(new, forward: true) }
            if host.noMatch && !find.isEmpty {
                Text("no match")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            if !find.isEmpty {
                Button { host.find(find, forward: false) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.plain).accessibilityLabel("Previous match")
                Button { host.find(find, forward: true) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.plain).accessibilityLabel("Next match")
                Button { find = ""; host.clear() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear find")
            }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .onReceive(NotificationCenter.default.publisher(for: .focusFind)) { _ in findFocused = true }
    }

    private func centered<V: View>(_ v: V) -> some View {
        VStack { Spacer(); v; Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Notification.Name {
    static let focusFind = Notification.Name("focusFind")
    static let focusSearch = Notification.Name("focusSearch")
}
