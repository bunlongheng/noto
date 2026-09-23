import Foundation
import AppKit
import SwiftUI
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

// MARK: - Submitter: the name the top-right chip and the footer show

let fromLaptop = Note(id: "1", title: "t", folderName: nil, folderColor: nil,
                      updatedAt: nil, createdAt: "2026-09-17T14:32:58Z", type: nil, content: nil, icon: nil,
                      createdByKey: "GV741W2732", createdByMachine: "GV741W2732")
T.equal("laptop notes are named by hostname", fromLaptop.submitterName, "GV741W2732")
let fromBrowser = Note(id: "1", title: "t", folderName: nil, folderColor: nil,
                       updatedAt: nil, createdAt: nil, type: nil, content: nil, icon: nil,
                       createdByKey: "stickies", createdByMachine: "10.0.0.9")
T.equal("the owner's own browser is \"me\"", fromBrowser.submitterName, "me")
T.equal("no attribution at all is still \"me\"", noDates.submitterName, "me")
let fromApp = Note(id: "1", title: "t", folderName: nil, folderColor: nil,
                   updatedAt: nil, createdAt: nil, type: nil, content: nil, icon: nil,
                   createdByKey: "automations-pipeline", createdByMachine: "M4")
T.equal("an app is named by its key", fromApp.submitterName, "automations-pipeline")
let fromHub = Note(id: "1", title: "t", folderName: nil, folderColor: nil,
                   updatedAt: nil, createdAt: nil, type: nil, content: nil, icon: nil,
                   createdByKey: "M4", createdByMachine: "M4")
T.check("the hub posting as itself shows the Mac mini, not the Stickies icon",
        fromHub.submitterIconURLs.first?.path.hasSuffix("/machines/mac-mini-front.png") == true)
T.check("an app on the hub keeps its own icon first",
        fromApp.submitterIconURLs.first?.path.hasSuffix("/app-icons/automations-pipeline.png") == true)
T.check("and falls back to the Mac mini, not Stickies, when that icon is missing",
        fromApp.submitterIconURLs.last?.path.hasSuffix("/machines/mac-mini-front.png") == true)
T.check("createdStamp carries a day and a time", fromLaptop.createdStamp.contains("\u{00B7}"))
T.check("createdAgo reads as relative", (fromLaptop.createdAgo ?? "").contains("ago"))
T.equal("createdAgo is nil without a timestamp", noDates.createdAgo, nil)

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

// MARK: - Renderer: a note may draw, but it may not phone home
//
// The line the app promises: note scripts RUN (reports chart with Chart.js and an
// inline script, and blocking them left empty boxes), but the network is shut -
// fetch, XHR and WebSocket all fail. The find highlighter runs in an isolated
// content world, which no CSP applies to, and must keep working either way.

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

    /// `.defaultClient` for anything the highlighter owns, `.page` for what a
    /// note's OWN script did. They are separate worlds: a page global read from
    /// the client world is always undefined, so a check written that way passes
    /// whether the script ran or not.
    func eval(_ js: String, in world: WKContentWorld = .defaultClient) -> Any? {
        var out: Any?
        var finished = false
        web.evaluateJavaScript(js, in: nil, in: world) { result in
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
<script>
  window.__ran = true;
  window.__fetchFailed = "pending";
  try {
    fetch("https://example.com/leak").then(function(){ window.__fetchFailed = "allowed"; },
                                           function(){ window.__fetchFailed = "blocked"; });
  } catch (e) { window.__fetchFailed = "blocked"; }
</script>
"""
let doc = """
<!doctype html><html><head><meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline' https://cdnjs.cloudflare.com https://cdn.jsdelivr.net; style-src 'unsafe-inline'; img-src data: https: http:; font-src data: https:; connect-src 'none'; form-action 'none'; base-uri 'none'; object-src 'none'">
</head><body>\(noteBody)</body></html>
"""

let probe = RenderProbe()
probe.run(doc)
T.check("the document finished loading", probe.done)

// The whole point of the change: a note's own script is allowed to draw.
let ran = probe.eval("String(window.__ran)", in: .page) as? String
T.equal("the note's inline script runs", ran ?? "nil", "true")

// And the half that must NOT move: no network out of a note.
var verdict = probe.eval("String(window.__fetchFailed)", in: .page) as? String
var waited = 0
while verdict == "pending" && waited < 40 {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    verdict = probe.eval("String(window.__fetchFailed)", in: .page) as? String
    waited += 1
}
T.equal("connect-src none blocks a note's fetch", verdict ?? "nil", "blocked")

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

// MARK: - The SwiftUI bridge
//
// The JS tests above run the highlighter in a bare WKWebView, which is exactly why
// they passed while the real feature was broken: HTMLView observed WebHost and
// reloaded the document on every published change, so each find keystroke restarted
// the page in a loop and wiped the highlights it had just drawn. These assertions
// drive find through the actual NSViewRepresentable.

func pump(_ seconds: TimeInterval) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
}

func pump(until condition: () -> Bool, timeout: TimeInterval = 20) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return condition()
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let bridgeHost = WebHost()
let bridgeView = HTMLView(html: noteBody, isHTML: true, host: bridgeHost)
let hosting = NSHostingView(rootView: bridgeView.frame(width: 600, height: 400))
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = hosting
window.orderBack(nil)

let mounted = pump(until: { bridgeHost.view != nil })
T.check("the representable mounted and handed over its web view", mounted)

// Wait for the note's own text to be in the DOM. `isLoading == false` is already
// true before the first load begins, so on a slower machine that check passed
// immediately, the marker below landed on about:blank, and the real load then
// wiped it - which is exactly how this failed in CI while passing locally.
let settled = pump(until: {
    guard let web = bridgeHost.view, !web.isLoading else { return false }
    var seen = false
    var done = false
    web.evaluateJavaScript("document.body.innerText.indexOf('The spam fix shipped') >= 0",
                           in: nil, in: .defaultClient) { r in
        seen = ((try? r.get()) as? Bool) ?? false
        done = true
    }
    let deadline = Date().addingTimeInterval(2)
    while !done && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return seen
}, timeout: 30)
T.check("the initial document finished loading", settled)

/// Plant a marker in the live page. A reload creates a fresh JS context, so if the
/// marker is gone afterwards the document was reloaded - which is the bug.
@MainActor func evalOnPage(_ js: String) -> Any? {
    guard let web = bridgeHost.view else { return nil }
    var out: Any?
    var done = false
    web.evaluateJavaScript(js, in: nil, in: .defaultClient) { r in
        out = try? r.get()
        done = true
    }
    _ = pump(until: { done }, timeout: 5)
    return out
}

_ = evalOnPage("window.__probe = 'alive'")
T.equal("the marker is set on the live page", evalOnPage("String(window.__probe)") as? String, "alive")

bridgeHost.find("spam")
_ = pump(until: { bridgeHost.matches > 0 }, timeout: 5)
pump(2.0)

T.equal("find through the bridge reports every match", bridgeHost.matches, 3)
T.equal("find through the bridge starts on the first match", bridgeHost.current, 1)
T.equal("find does NOT reload the document", evalOnPage("String(window.__probe)") as? String, "alive")

bridgeHost.step(true)
_ = pump(until: { bridgeHost.current == 2 }, timeout: 5)
T.equal("stepping advances instead of snapping back to the first match", bridgeHost.current, 2)
T.equal("stepping does NOT reload the document", evalOnPage("String(window.__probe)") as? String, "alive")

T.equal("the highlights survive in the live document",
        evalOnPage("document.querySelectorAll('mark.sn-hit').length") as? Int, 3)

// MARK: - Export: the WHOLE note, not the visible part

// The live view above is 600x400. A note taller than that must still come back
// whole - this is the one thing a takeSnapshot-based export gets wrong, so it is
// the thing worth asserting.
if let web = bridgeHost.view {
    var tallDone = false
    web.evaluateJavaScript("document.body.insertAdjacentHTML('beforeend', '<div style=\\'height:2400px\\'>tail</div>'); document.documentElement.scrollHeight",
                           in: nil, in: .defaultClient) { _ in tallDone = true }
    _ = pump(until: { tallDone }, timeout: 5)
    pump(0.5)

    var exported: CGImage?
    var exportFailed: String?
    Task { @MainActor in
        do { exported = try await NoteExport.fullPageImage(of: web, scale: 1) }
        catch { exportFailed = "\(error)" }
    }
    let captured = pump(until: { exported != nil || exportFailed != nil }, timeout: 30)
    T.check("the full-page export produced an image", captured && exported != nil, exportFailed ?? "timed out")

    if let image = exported {
        T.check("the export is the whole document, not the 400pt on screen",
                image.height > 1200, "got \(image.height)pt tall")
        T.check("the export keeps the rendered width", image.width >= 500, "got \(image.width)pt wide")

        let png = FileManager.default.temporaryDirectory.appendingPathComponent("noto-export-test.png")
        try? FileManager.default.removeItem(at: png)
        do {
            try NoteExport.write(image, to: png, format: .png)
            let size = ((try? FileManager.default.attributesOfItem(atPath: png.path)[.size]) as? Int) ?? 0
            T.check("PNG lands on disk with real bytes", size > 2000, "got \(size) bytes")
        } catch {
            T.check("PNG lands on disk with real bytes", false, "\(error)")
        }
        try? FileManager.default.removeItem(at: png)

        // Only where an encoder exists. The menu hides the option on a Mac without
        // one, so the suite skips it there too instead of failing.
        if NoteExport.webpEncoder != nil {
            let webp = FileManager.default.temporaryDirectory.appendingPathComponent("noto-export-test.webp")
            try? FileManager.default.removeItem(at: webp)
            do {
                try NoteExport.write(image, to: webp, format: .webp)
                let bytes = (try? Data(contentsOf: webp)) ?? Data()
                T.check("WebP lands on disk", bytes.count > 1000, "got \(bytes.count) bytes")
                T.check("WebP carries the RIFF/WEBP header",
                        bytes.count > 12 && Array(bytes[0..<4]) == Array("RIFF".utf8) && Array(bytes[8..<12]) == Array("WEBP".utf8))
            } catch {
                T.check("WebP lands on disk", false, "\(error)")
            }
            try? FileManager.default.removeItem(at: webp)
        }
    }
}

// Filenames: a title is free text, a filename is not.
T.equal("slashes never reach the filename", NoteExport.safeName("a/b:c"), "a b c")
T.equal("an empty title still saves", NoteExport.safeName("   "), "Note")
T.equal("a normal title is left alone", NoteExport.safeName("Resource Audit - 12h Rollup"), "Resource Audit - 12h Rollup")

// MARK: - The second paste is refused

func cmdV() -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                     windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v",
                     isARepeat: false, keyCode: 9)!
}

let clip = NSPasteboard.general
clip.clearContents()
clip.setString("Iframe", forType: .string)

let guarded = GuardedSearchField()
guarded.stringValue = "Iframe"
T.check("a paste that repeats the whole field is swallowed", guarded.performKeyEquivalent(with: cmdV()))
T.equal("the field is left holding one copy", guarded.stringValue, "Iframe")

// Trailing whitespace on either side is still the same paste.
guarded.stringValue = "Iframe "
T.check("whitespace does not sneak the repeat through", PasteGuard.blocks(cmdV(), current: guarded.stringValue))
guarded.stringValue = "iframe"
T.check("case does not sneak the repeat through", PasteGuard.blocks(cmdV(), current: guarded.stringValue))

// Everything that is a real edit still goes through.
guarded.stringValue = ""
T.check("pasting into an empty field is allowed", !PasteGuard.blocks(cmdV(), current: guarded.stringValue))
guarded.stringValue = "webview"
T.check("pasting a different word is allowed", !PasteGuard.blocks(cmdV(), current: guarded.stringValue))
guarded.stringValue = "Iframe Iframe"
T.check("a field that already differs from the clipboard is allowed",
        !PasteGuard.blocks(cmdV(), current: guarded.stringValue))

let typed = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                             windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v",
                             isARepeat: false, keyCode: 9)!
T.check("a plain v is not a paste", !PasteGuard.isPaste(typed))

clip.clearContents()
T.check("an empty clipboard blocks nothing", !PasteGuard.repeats("Iframe", clipboard: nil))
T.check("blank clipboard text blocks nothing", !PasteGuard.repeats("Iframe", clipboard: "   "))

let filter = GuardedTextField()
clip.clearContents()
clip.setString("Resource Audit", forType: .string)
filter.stringValue = "Resource Audit"
T.check("the sidebar filter carries the same guard", filter.performKeyEquivalent(with: cmdV()))

// MARK: - Share: the fields the owner path writes

// The server names these columns, not this app - a field spelled wrong here is a
// share toggle that returns 200 and changes nothing.
func shareJSON(_ f: ShareFields) -> [String: Any] {
    let data = try! JSONEncoder().encode(f)
    return (try! JSONSerialization.jsonObject(with: data)) as! [String: Any]
}
var fields = ShareFields(isPublic: true)
fields.id = "abc"
var json = shareJSON(fields)
T.equal("public goes out as is_public", json["is_public"] as? Bool, true)
T.check("a toggle sends only what it changes", json["locked"] == nil && json["frozen"] == nil)

// Locking implies sharing: the web toggle publishes the note at the same time, and
// sends the passcode in plaintext for the server to hash.
json = shareJSON(ShareFields(isPublic: true, locked: true, passcode: "s3cret"))
T.equal("the passcode goes out as lock_password", json["lock_password"] as? String, "s3cret")
T.equal("locking publishes at the same time", json["is_public"] as? Bool, true)

// Blank is a real answer, not a missing one - "shared, no gate".
json = shareJSON(ShareFields(locked: true, passcode: ""))
T.equal("an empty passcode is still sent", json["lock_password"] as? String, "")

json = shareJSON(ShareFields(frozen: false))
T.equal("releasing the write-protect sends frozen false", json["frozen"] as? Bool, false)
T.check("releasing it touches nothing else", json["is_public"] == nil && json["locked"] == nil)

// Share writes must NEVER go to the keyed /ext route: the server strips every
// share field from an API-key PATCH, so that request would silently do nothing.
T.equal("share writes use the owner path", Config.ownerPath, "/api/stickies")
T.check("the owner path is not the keyed one", Config.ownerPath != Config.notesPath)
// A localhost link is useless to whoever it is sent to.
T.check("the share link points at the public deployment",
        Config.shareBaseURL.hasPrefix("https://") && !Config.shareBaseURL.contains("localhost"))

T.report()
