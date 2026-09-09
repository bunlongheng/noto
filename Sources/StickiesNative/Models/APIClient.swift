import Foundation

enum APIError: LocalizedError {
    case noKey
    case badStatus(Int)
    case forbidden

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "No API key. Add STICKIES_API_KEY to ~/.stickies-native.env"
        case .badStatus(let code):
            return code == 401 ? "Key rejected (401)" : "Server returned HTTP \(code)"
        case .forbidden:
            return "The server refused this change (403)"
        }
    }
}

/// Read-only client for the Stickies ext API. Fetch only - this app never writes.
struct APIClient {
    private let pageSize = 100
    private let hardCap = 10_000   // stop runaway paging if the server ever misbehaves

    /// Every note, paged until the server stops returning full pages.
    /// The list endpoint omits note bodies, so this stays cheap no matter the count.
    func fetchAllNotes() async throws -> [Note] {
        guard let key = Config.apiKey else { throw APIError.noKey }
        var all: [Note] = []
        var offset = 0

        while all.count < hardCap {
            let path = "/api/stickies/ext?recent=all&limit=\(pageSize)&offset=\(offset)"
            guard let url = URL(string: Config.appBaseURL + path) else { break }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
            guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }

            let page = try JSONDecoder().decode(NotesResponse.self, from: data).notes
            all.append(contentsOf: page)
            if page.count < pageSize { break }   // short page = last page
            offset += pageSize
        }
        // Server order is created_at DESC (the web All view). Never re-sort here.
        return all
    }

    /// One note WITH its body. The list endpoint omits content, so this runs only
    /// when a row is selected.
    func fetchNote(id: String) async throws -> Note {
        guard let key = Config.apiKey else { throw APIError.noKey }
        guard let url = URL(string: Config.appBaseURL + "/api/stickies/ext?id=" + id) else {
            throw APIError.badStatus(0)
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
        guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(SingleNoteResponse.self, from: data).note
    }

    /// Move a note to TRASH - the same soft delete the web app performs
    /// (app/(app)/page.tsx:2613). A hard DELETE is refused for API keys by design
    /// (app/api/stickies/route.ts:1066), and trashed notes are purged by the
    /// server's own 7 day expiry, so nothing is destroyed here.
    func trash(id: String) async throws {
        guard let key = Config.apiKey else { throw APIError.noKey }
        guard let url = URL(string: Config.appBaseURL + "/api/stickies/ext") else {
            throw APIError.badStatus(0)
        }
        let payload: [String: String] = [
            "id": id,
            "folder_name": "TRASH",
            "trashed_at": ISO8601DateFormatter().string(from: Date()),
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 20

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
        if http.statusCode == 403 { throw APIError.forbidden }
        guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }
}
