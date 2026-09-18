import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var folderName: String?
    var folderColor: String?
    var updatedAt: String?
    var createdAt: String?
    var type: String?
    var content: String?
    var icon: String?
    /// Shared with anyone who has the link.
    var isPublic: Bool?
    /// Share is passcode-gated.
    var locked: Bool?
    /// Write-protected: the server refuses every edit AND the trash move (423).
    var frozen: Bool?
    /// Which app posted it, and from which machine - the same attribution the web
    /// list badges each row with.
    var createdByKey: String?
    var createdByMachine: String?
    /// When it was trashed - the server purges TRASH on its own 7 day schedule.
    var trashedAt: String?
    /// Survives the trash move, so it is how a restore finds its way home.
    var folderId: String?

    enum CodingKeys: String, CodingKey {
        case id, title, type, content, icon, locked, frozen
        case folderName = "folder_name"
        case folderColor = "folder_color"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case isPublic = "is_public"
        case createdByKey = "created_by_key"
        case createdByMachine = "created_by_machine"
        case trashedAt = "trashed_at"
        case folderId = "folder_id"
    }

    /// The All view is ordered by created_at server-side, so show creation time -
    /// matching components/NoteTileListBody.tsx:185 in the web app. Falling back to
    /// updated_at only when a row has no created_at.
    /// Formatters are expensive to build and were being allocated twice per row per
    /// render - 204ms to lay out 1,386 rows. Built once and reused. Foundation
    /// formatters have been documented thread-safe since macOS 10.9 but are not
    /// annotated Sendable, hence nonisolated(unsafe); they are only ever read.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let timeOnly: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let dayMonth: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d"); return f
    }()
    private static let withYear: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .none; return f
    }()

    var date: Date? {
        guard let stamp = createdAt ?? updatedAt else { return nil }
        return Note.isoFractional.date(from: stamp) ?? Note.iso.date(from: stamp)
    }

    /// Short by design: a full "Sep 10, 2026 at 12:09 PM" ate about 150pt of a
    /// 328pt row and truncated most titles to roughly 15 characters.
    var displayDate: String {
        guard let stamp = createdAt ?? updatedAt else { return "" }
        guard let date else { return stamp }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return Note.timeOnly.string(from: date) }
        if cal.component(.year, from: date) == cal.component(.year, from: Date()) {
            return Note.dayMonth.string(from: date)
        }
        return Note.withYear.string(from: date)
    }

    /// The web footer's stamp: "Sep 17 · 2:32 PM".
    var createdStamp: String {
        guard let date else { return displayDate }
        return Note.dayMonth.string(from: date) + " · " + Note.timeOnly.string(from: date)
    }

    nonisolated(unsafe) private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
    /// "2 hr. ago", next to the stamp, as the web footer shows it.
    var createdAgo: String? {
        guard let date else { return nil }
        return Note.relative.localizedString(for: date, relativeTo: Date())
    }

    /// Who posted it, named the way the web footer names it: the work laptop by
    /// its hostname, an app by its key, and the owner's own browser as "me".
    var submitterName: String {
        if createdByMachine == "GV741W2732" { return "GV741W2732" }
        let key = createdByKey ?? ""
        if key.isEmpty || key == "stickies" { return "me" }
        return key
    }

    /// Lowercased title + folder, computed once, so the search filter is a plain
    /// substring test rather than a locale-aware compare over every note per keystroke.
    var searchKey: String { (title + " " + (folderName ?? "")).lowercased() }

    /// Days before the server purges this note for good, or nil when it is not in
    /// TRASH. Matches the web app's "Nd left".
    var daysLeft: Int? {
        guard let stamp = trashedAt,
              let date = Note.isoFractional.date(from: stamp) ?? Note.iso.date(from: stamp)
        else { return nil }
        let gone = date.addingTimeInterval(7 * 86_400)
        return max(0, Int(gone.timeIntervalSinceNow / 86_400) + 1)
    }

    /// Candidate badges for who posted this note, best first, each served by the
    /// notes app itself.
    ///
    /// Same order the web list uses - work laptop's device icon outright, the
    /// owner's avatar for a note written in the browser, otherwise the posting
    /// app's icon - and the same suffix rule, so "automations-pipeline" falls back
    /// to "automations". The last entry is the default icon: a 404 must never leave
    /// a row showing two mystery letters.
    ///
    /// The hub is the exception to the web's rule: there its badge is hidden as
    /// noise, here a note M4 posted under its own name (or none) shows the Mac mini,
    /// the same front-view art the drops app uses, never the Stickies icon.
    var submitterIconURLs: [URL] {
        let base = Config.appBaseURL
        let hub = createdByMachine == "M4"
        let hubIcon = URL(string: base + "/machines/mac-mini-front.png")
        let fallback = hub ? hubIcon : URL(string: base + "/app-icons/stickies.png")
        if createdByMachine == "GV741W2732" {
            return [URL(string: base + "/machines/macbook-m2.png?v=3"), fallback].compactMap { $0 }
        }
        let key = (createdByKey ?? "").lowercased()
        guard !key.isEmpty, key != "stickies", key != "m4" else {
            return [hub ? hubIcon : URL(string: base + "/avatar.png"), fallback].compactMap { $0 }
        }
        var candidates = [URL(string: base + "/app-icons/\(key).png")]
        let head = key.split(separator: "-").first.map(String.init) ?? key
        if head != key { candidates.append(URL(string: base + "/app-icons/\(head).png")) }
        candidates.append(fallback)
        return candidates.compactMap { $0 }
    }

    /// #RRGGBB from the folder, or nil when absent or malformed.
    var parsedColor: (r: Double, g: Double, b: Double)? {
        guard let hex = folderColor, hex.hasPrefix("#"), hex.count == 7,
              let val = UInt64(hex.dropFirst(), radix: 16) else { return nil }
        return (Double((val >> 16) & 0xFF) / 255, Double((val >> 8) & 0xFF) / 255, Double(val & 0xFF) / 255)
    }
}

struct NotesResponse: Codable {
    let notes: [Note]
    /// The server sends COUNT(*) OVER() on every page; used to show progress.
    let total: Int?
}
struct SingleNoteResponse: Codable { let note: Note }
