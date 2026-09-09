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
    var displayDate: String {
        guard let updatedAt = createdAt ?? updatedAt else { return "" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: updatedAt) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: updatedAt)
        }()
        guard let date else { return updatedAt }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    /// #RRGGBB from the folder, or nil when absent or malformed.
    var parsedColor: (r: Double, g: Double, b: Double)? {
        guard let hex = folderColor, hex.hasPrefix("#"), hex.count == 7,
              let val = UInt64(hex.dropFirst(), radix: 16) else { return nil }
        return (Double((val >> 16) & 0xFF) / 255, Double((val >> 8) & 0xFF) / 255, Double(val & 0xFF) / 255)
    }
}

struct NotesResponse: Codable { let notes: [Note] }
struct SingleNoteResponse: Codable { let note: Note }
