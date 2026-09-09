import SwiftUI
import WebKit

/// Read-only HTML renderer. JavaScript is off: these notes are self-contained
/// markup and a viewer has no reason to execute anything they carry.
struct HTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")   // let the note's own bg show
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        view.loadHTMLString(wrapped, baseURL: URL(string: Config.appBaseURL))
    }

    /// Notes are body fragments, so give them a viewport and a readable base style.
    private var wrapped: String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          :root { color-scheme: light dark; }
          body { margin:0; padding:18px; font:14px/1.55 -apple-system,BlinkMacSystemFont,system-ui,sans-serif; }
          img, table { max-width:100%; }
          pre { overflow-x:auto; }
        </style></head><body>\(html)</body></html>
        """
    }
}

struct NoteDetailView: View {
    let note: Note
    @EnvironmentObject var state: AppState
    @State private var body_: String?
    @State private var error: String?

    var body: some View {
        Group {
            if let error {
                centered(Text(error).foregroundStyle(.secondary))
            } else if let body_ {
                if (note.type ?? "") == "html" {
                    HTMLView(html: body_)
                } else {
                    ScrollView {
                        Text(body_)
                            .font(.system(size: 13))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                    }
                }
            } else {
                centered(ProgressView())
            }
        }
        .navigationTitle(note.title)
        .task(id: note.id) {
            body_ = nil
            error = nil
            do {
                body_ = try await state.api.fetchNote(id: note.id).content ?? ""
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
