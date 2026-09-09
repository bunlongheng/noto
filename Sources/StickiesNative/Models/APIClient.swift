import Foundation

enum APIError: LocalizedError {
    case noKey
    case badStatus(Int)

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "No API key. Add STICKIES_API_KEY to ~/.stickies-native.env"
        case .badStatus(let code):
            return code == 401 ? "Key rejected (401)" : "Server returned HTTP \(code)"
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
        return all
    }
}
