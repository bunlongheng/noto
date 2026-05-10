import Foundation

struct Note: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var content: String?
    var folderName: String?
    var folderColor: String?
    var updatedAt: String?
    var type: String?

    enum CodingKeys: String, CodingKey {
        case id, title, content, type
        case folderName = "folder_name"
        case folderColor = "folder_color"
        case updatedAt = "updated_at"
    }

    var displayDate: String {
        guard let updatedAt else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: updatedAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: updatedAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return updatedAt
    }

    var parsedColor: (r: Double, g: Double, b: Double)? {
        guard let hex = folderColor, hex.hasPrefix("#"), hex.count == 7 else { return nil }
        let start = hex.index(hex.startIndex, offsetBy: 1)
        let hexStr = String(hex[start...])
        guard let val = UInt64(hexStr, radix: 16) else { return nil }
        return (
            r: Double((val >> 16) & 0xFF) / 255.0,
            g: Double((val >> 8) & 0xFF) / 255.0,
            b: Double(val & 0xFF) / 255.0
        )
    }
}

struct NotesResponse: Codable {
    let notes: [Note]
}

struct SingleNoteResponse: Codable {
    let note: Note
}
