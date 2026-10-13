import AppKit
import WebKit

/// The note as it reads: the rendered HTML with its inline styling, plus a plain
/// text fallback. Mail and Gmail take the HTML flavour, so an email drafted as a
/// note pastes in looking like the note.
enum RichCopy {
    private static let script = "({ html: document.body.innerHTML, text: document.body.innerText })"

    @MainActor
    static func copy(from view: WKWebView?) async -> (Toast.Kind, String) {
        guard let view else { return (.failure, "Nothing to copy yet") }
        do {
            let result = try await view.evaluateJavaScript(script, in: nil, contentWorld: .defaultClient) as? [String: Any]
            let html = result?["html"] as? String ?? ""
            let text = result?["text"] as? String ?? ""
            let page = "<!doctype html><html><head><meta charset=\"utf-8\"></head><body>\(html)</body></html>"
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(page, forType: .html)
            board.setString(text, forType: .string)
            return (.success, "Note copied, ready to paste")
        } catch {
            return (.failure, "Could not read the note: \(error.localizedDescription)")
        }
    }
}
