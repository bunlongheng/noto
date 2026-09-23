import Foundation

enum APIError: LocalizedError {
    case noKey
    case badStatus(Int)
    case forbidden
    case locked

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "No API key. Add NOTO_API_KEY to ~/.noto.env"
        case .badStatus(let code):
            return code == 401 ? "Key rejected (401)" : "Server returned HTTP \(code)"
        case .forbidden:
            return "The server refused this change (403)"
        case .locked:
            return "That note is locked. Unlock it in the web app first"
        }
    }
}

/// The share flags, exactly as the server names them. A field left nil is left
/// out of the request entirely, so each toggle sends only what it changes.
/// `passcode` is the plaintext the server hashes - the hash column itself is
/// server-managed and refuses a client write.
struct ShareFields: Encodable, Sendable {
    var id: String?
    var isPublic: Bool?
    var locked: Bool?
    var passcode: String?
    var frozen: Bool?

    enum CodingKeys: String, CodingKey {
        case id, locked, frozen
        case isPublic = "is_public"
        case passcode = "lock_password"
    }
}

/// Client for the notes API. Reads the list and one note at a time, creates a
/// plain-text note, searches bodies, and moves a note to TRASH.
struct APIClient {
    private let pageSize = 100
    private let hardCap = 10_000   // stop runaway paging if the server ever misbehaves

    /// Every note, paged until the server stops returning full pages.
    ///
    /// `onPage` is called with the running total after each page, so the list can
    /// render the first 100 notes in about 150ms instead of staying blank for the
    /// ~2.6s the full crawl takes. A page that fails keeps everything already
    /// fetched rather than discarding the whole crawl.
    func fetchAllNotes(onPage: (@MainActor ([Note], Int?) -> Void)? = nil) async throws -> [Note] {
        guard let key = Config.apiKey else { throw APIError.noKey }
        var all: [Note] = []
        var offset = 0
        var total: Int?

        while all.count < hardCap {
            let path = Config.notesPath + "?recent=all&limit=\(pageSize)&offset=\(offset)"
            guard let url = URL(string: Config.appBaseURL + path) else { break }

            var request = URLRequest(url: url)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
            guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }

            let decoded = try JSONDecoder().decode(NotesResponse.self, from: data)
            total = decoded.total ?? total
            all.append(contentsOf: decoded.notes)
            if let onPage {
                let snapshot = all
                let count = total
                await MainActor.run { onPage(snapshot, count) }
            }
            if decoded.notes.count < pageSize { break }   // short page = last page
            offset += pageSize
            try Task.checkCancellation()
        }
        // Server order is created_at DESC (the web All view). Never re-sort here.
        return all
    }

    /// One note WITH its body. The list endpoint omits content, so this runs only
    /// when a row is selected.
    func fetchNote(id: String) async throws -> Note {
        guard let key = Config.apiKey else { throw APIError.noKey }
        guard let url = URL(string: Config.appBaseURL + Config.notesPath + "?id=" + id) else {
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

    /// Server-side search. The list endpoint never sends note bodies, so matching
    /// anything but a title has to happen where the content actually lives. The
    /// server caps this at 50 rows and matches title OR content.
    func search(_ q: String) async throws -> [Note] {
        guard let key = Config.apiKey else { throw APIError.noKey }
        var components = URLComponents(string: Config.appBaseURL + Config.notesPath)
        components?.queryItems = [URLQueryItem(name: "q", value: q)]
        guard let url = components?.url else { throw APIError.badStatus(0) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
        guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(NotesResponse.self, from: data).notes
    }

    /// Create a plain-text note. `type: "text"` is sent explicitly because the
    /// server otherwise sniffs the body and would file a note that happens to open
    /// with a tag or a brace as html/json.
    func create(title: String, content: String) async throws -> Note {
        guard let key = Config.apiKey else { throw APIError.noKey }
        guard let url = URL(string: Config.appBaseURL + Config.notesPath) else {
            throw APIError.badStatus(0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["title": title, "content": content, "type": "text"])
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
        if http.statusCode == 403 { throw APIError.forbidden }
        guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(SingleNoteResponse.self, from: data).note
    }

    /// Everything in TRASH. Its own call: the list endpoint filters trashed notes
    /// out by design, so the main list can never show them.
    func fetchTrash() async throws -> [Note] {
        guard let key = Config.apiKey else { throw APIError.noKey }
        guard let url = URL(string: Config.appBaseURL + Config.notesPath + "?folder=TRASH&limit=500")
        else { throw APIError.badStatus(0) }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
        guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(NotesResponse.self, from: data).notes
    }

    /// Delete every note in TRASH, permanently. There is no undo for this one.
    ///
    /// NOT the ext API: an API key may never delete (403 by design, so a leaked key
    /// cannot destroy notes). The owner path is a KEY-LESS request, which the server
    /// trusts only from this machine - exactly the guarantee this call wants. The
    /// server deletes the notes inside TRASH and never the folder row itself.
    func emptyTrash() async throws {
        guard let url = URL(string: Config.appBaseURL + "/api/stickies?folder_name=TRASH") else {
            throw APIError.badStatus(0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.forbidden }
        guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }

    /// Put a note back where it was. The inverse of `trash`.
    ///
    /// `trashed_at` MUST be null, not "" - the column is a timestamp, and an empty
    /// string made Postgres reject the UPDATE, so every Undo came back 500 and the
    /// note stayed in TRASH.
    func restore(id: String, toFolder folder: String?) async throws {
        try await patch(["id": id, "folder_name": folder ?? "", "trashed_at": nil])
    }

    /// Move a note to TRASH - the same soft delete the web app performs
    /// (app/(app)/page.tsx:2613). A hard DELETE is refused for API keys by design
    /// (app/api/stickies/route.ts:1066), and trashed notes are purged by the
    /// server's own 7 day expiry, so nothing is destroyed here.
    func trash(id: String) async throws {
        try await patch([
            "id": id,
            "folder_name": "TRASH",
            "trashed_at": ISO8601DateFormatter().string(from: Date()),
        ])
    }

    private func patch(_ payload: [String: String?]) async throws {
        guard let key = Config.apiKey else { throw APIError.noKey }
        guard let url = URL(string: Config.appBaseURL + Config.notesPath) else {
            throw APIError.badStatus(0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 20

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
        if http.statusCode == 403 { throw APIError.forbidden }
        // 423 is the server's write-protect on a frozen note - it refuses the trash
        // move as firmly as it refuses an edit. The list's frozen flag is checked
        // first, but it can be stale: the web app may have frozen the note since.
        if http.statusCode == 423 { throw APIError.locked }
        guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }

    /// Change a note's share state: public, passcode-gated, or write-protected.
    ///
    /// Goes to the KEY-LESS owner path, not /ext. The server strips is_public,
    /// locked and lock_password from every API-key PATCH by design
    /// (app/api/stickies/route.ts:1316), so the keyed request this app uses for
    /// everything else comes back 200 having changed nothing at all. The keyless
    /// path is trusted only from this machine - the same route emptyTrash takes.
    func setShare(id: String, _ fields: ShareFields) async throws {
        guard let url = URL(string: Config.appBaseURL + Config.ownerPath) else {
            throw APIError.badStatus(0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = fields
        body.id = id
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 20

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(0) }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIError.forbidden }
        if http.statusCode == 423 { throw APIError.locked }
        guard (200...299).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }
}
