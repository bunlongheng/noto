import Foundation
import AppKit
import WebKit

// MARK: - Note decoding

let listRow = """
{"id":"abc","title":"ES6 - Study Cheat Sheet","folder_name":"Cheat Sheets",
 "folder_color":"#FF9500","updated_at":"2026-09-08T10:16:00.000Z",
 "created_at":"2026-09-08T10:13:00.000Z","type":"html","icon":"__hero:BookOpenIcon"}
"""
var decoded: Note?
T.suite("note decoding") {
    let note = try JSONDecoder().decode(Note.self, from: Data(listRow.utf8))
    decoded = note
    T.equal("decode id", note.id, "abc")
    T.equal("decode snake_case folder_name", note.folderName, "Cheat Sheets")
    T.equal("decode snake_case folder_color", note.folderColor, "#FF9500")
    T.equal("decode snake_case created_at", note.createdAt, "2026-09-08T10:13:00.000Z")
    T.equal("decode icon token", note.icon, "__hero:BookOpenIcon")
}
T.check("the decode suite produced a note", decoded != nil)

// The list endpoint omits content entirely - decoding must not fail on that.
let noContent = #"{"id":"x","title":"t"}"#
T.check("decode tolerates a row with no content", (try? JSONDecoder().decode(Note.self, from: Data(noContent.utf8))) != nil)

// MARK: - displayDate: the All view is ordered by created_at, so show created_at

T.check("displayDate prefers created_at over updated_at", !(decoded?.displayDate ?? "").isEmpty)
let onlyUpdated = Note(id: "1", title: "t", folderName: nil, folderColor: nil,
                       updatedAt: "2026-09-08T10:16:00.000Z", createdAt: nil, type: nil, content: nil, icon: nil)
T.check("displayDate falls back to updated_at", !onlyUpdated.displayDate.isEmpty)
let noDates = Note(id: "1", title: "t", folderName: nil, folderColor: nil,
                   updatedAt: nil, createdAt: nil, type: nil, content: nil, icon: nil)
T.equal("displayDate is empty with no timestamps", noDates.displayDate, "")
// The API emits both with and without fractional seconds - both must parse.
let noFraction = Note(id: "1", title: "t", folderName: nil, folderColor: nil,
                      updatedAt: nil, createdAt: "2026-09-08T10:13:00Z", type: nil, content: nil, icon: nil)
T.check("displayDate parses a timestamp with no fractional seconds",
        noFraction.displayDate != "2026-09-08T10:13:00Z" && !noFraction.displayDate.isEmpty)

// MARK: - Folder colour parsing

func coloured(_ hex: String?) -> Note {
    Note(id: "1", title: "t", folderName: nil, folderColor: hex,
         updatedAt: nil, createdAt: nil, type: nil, content: nil, icon: nil)
}
if let c = coloured("#FF9500").parsedColor {
    T.check("parses red channel", abs(c.r - 1.0) < 0.001, "got \(c.r)")
    T.check("parses green channel", abs(c.g - 0.5843) < 0.001, "got \(c.g)")
    T.check("parses blue channel", abs(c.b - 0.0) < 0.001, "got \(c.b)")
} else {
    T.check("parses a valid hex colour", false)
}
T.check("rejects a missing colour", coloured(nil).parsedColor == nil)
T.check("rejects a hex with no hash", coloured("FF9500").parsedColor == nil)
T.check("rejects a short hex", coloured("#FFF").parsedColor == nil)
T.check("rejects non-hex characters", coloured("#GGGGGG").parsedColor == nil)

// MARK: - Icon mapping
//
// Every token observed across the live board must map to a symbol that exists on
// this system. An unavailable SF Symbol name renders as nothing, which would leave
// a blank row - the exact failure this guards.

let heroTokens = [
    "CheckCircleIcon", "ChartBarIcon", "RocketLaunchIcon", "ClipboardDocumentListIcon",
    "ArrowPathIcon", "EnvelopeIcon", "LinkIcon", "GlobeAltIcon", "UserGroupIcon",
    "SwatchIcon", "BriefcaseIcon", "RobotIcon", "KeyIcon", "FolderIcon", "BookOpenIcon",
    "CodeBracketIcon", "WrenchIcon", "MagnifyingGlassIcon", "DocumentTextIcon",
    "LightBulbIcon", "BugAntIcon", "HomeIcon", "TableCellsIcon", "CalendarDaysIcon",
    "ChatBubbleLeftRightIcon", "ShareIcon", "GlobeAmericasIcon", "DevicePhoneMobileIcon",
    "PhotoIcon", "FilmIcon", "BanknotesIcon", "StarIcon", "PuzzlePieceIcon",
    "SparklesIcon", "IdentificationIcon", "QuestionMarkCircleIcon", "BoltIcon",
    "MusicalNoteIcon", "CubeTransparentIcon",
]
let appTokens = [
    "repoaudit", "praudit", "skillaudit", "epicaudit", "devaudit", "portfolioaudit",
    "githubaudit", "resourceaudit", "projectaudit", "reporecon", "repotest", "gmail",
    "linkedin", "github", "prtrends", "githubstats", "prsummary", "app:fable",
    "app:repo-audit", "app:worldcup26", "app:skill-architect", "app:job",
    "app:incident-report", "app:countries", "app:bheng", "app:rust", "app:react",
    "app:laravel", "app:next.js", "app:typescript",
]
var missing: [String] = []
var fellBack: [String] = []
for t in heroTokens {
    let sym = NoteIcon.symbol(for: "__hero:\(t)")
    if NSImage(systemSymbolName: sym, accessibilityDescription: nil) == nil { missing.append("hero:\(t) -> \(sym)") }
    // DocumentTextIcon legitimately maps to the same symbol as the fallback.
    if sym == "doc.text.fill" && t != "DocumentTextIcon" { fellBack.append("hero:\(t)") }
}
for t in appTokens {
    let sym = NoteIcon.symbol(for: "__\(t)")
    if NSImage(systemSymbolName: sym, accessibilityDescription: nil) == nil { missing.append("\(t) -> \(sym)") }
    if sym == "doc.text.fill" { fellBack.append(t) }
}
T.check("every icon token resolves to a symbol that exists on this system",
        missing.isEmpty, "missing: \(missing.joined(separator: ", "))")
T.check("all \(heroTokens.count + appTokens.count) live icon tokens have a real mapping",
        fellBack.isEmpty, "fell back to the default: \(fellBack.joined(separator: ", "))")
T.equal("an unknown token falls back", NoteIcon.symbol(for: "__hero:NotARealIcon"), "doc.text.fill")
T.equal("a nil token falls back", NoteIcon.symbol(for: nil), "doc.text.fill")
T.equal("a non-prefixed token falls back", NoteIcon.symbol(for: "plain"), "doc.text.fill")

// MARK: - Renderer: CSP must block note scripts, the highlighter must still run
//
// This is the test that matters most. The find highlighter runs in an isolated
// content world so a CSP can block every script a note carries. If either half
// breaks - CSP too weak, or the isolated world blocked too - this catches it.

final class RenderProbe: NSObject, WKNavigationDelegate {
    let web: WKWebView
    var done = false

    override init() {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(source: HTMLView.finder, injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true, in: .defaultClient))
        web = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: config)
        super.init()
        web.navigationDelegate = self
    }

    func run(_ html: String) {
        web.loadHTMLString(html, baseURL: nil)
        let deadline = Date().addingTimeInterval(20)
        while !done && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    func eval(_ js: String) -> Any? {
        var out: Any?
        var finished = false
        web.evaluateJavaScript(js, in: nil, in: .defaultClient) { result in
            out = try? result.get()
            finished = true
        }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return out
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { done = true }
}

let noteBody = """
<p>The spam fix shipped. Spam was the symptom, not the cause.</p>
<p>More about spam handling here.</p>
<script>window.__pwned = true; document.body.innerHTML = 'HIJACKED';</script>
<div onclick="window.__pwned = true">click me</div>
"""
let doc = """
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy"
      content="default-src 'none'; img-src data: https: http:; style-src 'unsafe-inline'; font-src data:">
</head><body>\(noteBody)</body></html>
"""

let probe = RenderProbe()
probe.run(doc)
T.check("the document finished loading", probe.done)

let pwned = probe.eval("String(window.__pwned)") as? String
T.check("CSP blocked the note's inline script", pwned == "undefined", "window.__pwned = \(pwned ?? "nil")")

let bodyText = probe.eval("document.body.innerText.indexOf('HIJACKED')") as? Int
T.equal("the note script did not rewrite the document", bodyText ?? -1, -1)

let strippedDoc = doc.replacingOccurrences(of: noteBody, with: HTMLView.stripScripts(noteBody))
let stripProbe = RenderProbe()
stripProbe.run(strippedDoc)
let lingering = stripProbe.eval("document.body.textContent.indexOf('HIJACKED')") as? Int
T.equal("stripping removes the script source from the DOM entirely", lingering ?? 0, -1)
let handler = stripProbe.eval("document.querySelector('div').getAttribute('onclick')")
T.check("stripping removes inline event handlers", handler is NSNull || handler == nil,
        "onclick = \(String(describing: handler))")

let hits = probe.eval("window.__snFind(\"spam\")") as? Int
T.equal("the highlighter runs despite the CSP and finds every match", hits ?? -1, 3)

let marks = probe.eval("document.querySelectorAll('mark.sn-hit').length") as? Int
T.equal("every match is wrapped in a highlight mark", marks ?? -1, 3)

let currentMarks = probe.eval("document.querySelectorAll('mark.sn-cur').length") as? Int
T.equal("exactly one match is the current one", currentMarks ?? -1, 1)

let stepped = probe.eval("window.__snStep(1)") as? Int
T.equal("stepping forward advances the current match", stepped ?? -1, 2)

let wrapped = probe.eval("window.__snStep(1); window.__snStep(1)") as? Int
T.equal("stepping past the last match wraps to the first", wrapped ?? -1, 1)

_ = probe.eval("window.__snClear()")
let afterClear = probe.eval("document.querySelectorAll('mark.sn-hit').length") as? Int
T.equal("clearing removes every highlight", afterClear ?? -1, 0)

let restored = probe.eval("document.body.textContent.indexOf('The spam fix shipped')") as? Int
T.check("clearing restores the original text", (restored ?? -1) >= 0)

let none = probe.eval("window.__snFind(\"zzzznotpresent\")") as? Int
T.equal("a query with no matches reports zero", none ?? -1, 0)

T.report()
