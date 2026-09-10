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

    enum CodingKeys: String, CodingKey {
        case id, title, type, content, icon
        case folderName = "folder_name"
        case folderColor = "folder_color"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
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

    /// Lowercased title + folder, computed once, so the search filter is a plain
    /// substring test rather than a locale-aware compare over every note per keystroke.
    var searchKey: String { (title + " " + (folderName ?? "")).lowercased() }

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
