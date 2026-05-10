import Foundation

final class APIClient: Sendable {
    private let baseURL = "https://stickies-bheng.vercel.app"
    private var apiKey: String {
        if let key = ProcessInfo.processInfo.environment["STICKIES_API_KEY"], !key.isEmpty {
            return key
        }
        return Config.apiKey
    }

    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: body)
        }

        return data
    }

    func fetchNotes(limit: Int = 50) async throws -> [Note] {
        let data = try await makeRequest(path: "/api/stickies/ext?limit=\(limit)")
        let response = try JSONDecoder().decode(NotesResponse.self, from: data)
        return response.notes
    }

    func fetchNote(id: String) async throws -> Note {
        let data = try await makeRequest(path: "/api/stickies/ext?id=\(id)")
        let response = try JSONDecoder().decode(SingleNoteResponse.self, from: data)
        return response.note
    }

    func updateNote(id: String, content: String) async throws {
        let payload: [String: String] = ["id": id, "content": content]
        let body = try JSONEncoder().encode(payload)
        _ = try await makeRequest(path: "/api/stickies/ext", method: "PATCH", body: body)
    }

    func createNote(title: String, content: String, folderName: String) async throws -> Note {
        let payload: [String: String] = [
            "title": title,
            "content": content,
            "folder_name": folderName
        ]
        let body = try JSONEncoder().encode(payload)
        let data = try await makeRequest(path: "/api/stickies/ext", method: "POST", body: body)

        // The POST response may vary - try to decode a note from it
        if let response = try? JSONDecoder().decode(SingleNoteResponse.self, from: data) {
            return response.note
        }

        // Fallback: create a local note object
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let id = json?["id"] as? String ?? UUID().uuidString
        return Note(
            id: id,
            title: title,
            content: content,
            folderName: folderName,
            folderColor: nil,
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            type: "text"
        )
    }
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        }
    }
}
