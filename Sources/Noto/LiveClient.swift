import Foundation

/// Live updates from the server, over the same Pusher channel the web app listens
/// on. Pusher's wire protocol is 3 messages - connect, subscribe, ping - so it is
/// spoken directly over URLSessionWebSocketTask rather than pulling in a package.
///
/// Every note event, and every reconnect, calls `onChange`; the caller's delta
/// pull does the actual work, so whatever happened while the socket was down is
/// caught up the moment it comes back. Without a key there is no live client at
/// all and Refresh does everything it did before.
actor LiveClient {
    static func socketURL(key: String, cluster: String) -> URL? {
        URL(string: "wss://ws-\(cluster).pusher.com/app/\(key)?protocol=7&client=noto&version=1.0")
    }

    /// The event name in a Pusher frame, or nil for anything that is not one.
    static func event(in text: String) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return nil }
        return obj["event"] as? String
    }

    /// What a note-deleted frame removed: one note by id, or every note in a
    /// folder. A hard delete never shows up in a delta pull, so the frame is the
    /// only word the client gets of it. Pusher sends `data` as a JSON string.
    static func deleted(in text: String) -> (id: String?, folder: String?)? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let raw = obj["data"] as? String,
              let data = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] else { return nil }
        let id = data["id"] as? String, folder = data["folder_name"] as? String
        return id == nil && folder == nil ? nil : (id, folder)
    }

    private let url: URL
    private let onChange: @MainActor @Sendable () -> Void
    private let onDelete: @MainActor @Sendable (String?, String?) -> Void
    private var loop: Task<Void, Never>?
    private var connections = 0

    init?(key: String?, cluster: String?,
          onDelete: @escaping @MainActor @Sendable (String?, String?) -> Void = { _, _ in },
          onChange: @escaping @MainActor @Sendable () -> Void) {
        guard let key, let cluster, let url = Self.socketURL(key: key, cluster: cluster) else { return nil }
        self.url = url
        self.onChange = onChange
        self.onDelete = onDelete
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { await run() }
    }

    private func run() async {
        var delay: Duration = .seconds(1)
        while !Task.isCancelled {
            let socket = URLSession.shared.webSocketTask(with: url)
            socket.resume()
            // Pusher drops a socket idle past its activity timeout (120s); a ping
            // well inside that keeps it open through a quiet afternoon.
            let keepAlive = Task {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(60))
                    try await socket.send(.string(#"{"event":"pusher:ping","data":{}}"#))
                }
            }
            var refused = false
            do {
                while !Task.isCancelled {
                    guard case .string(let text) = try await socket.receive() else { continue }
                    switch Self.event(in: text) {
                    case "pusher:connection_established":
                        try await socket.send(.string(#"{"event":"pusher:subscribe","data":{"channel":"stickies"}}"#))
                        delay = .seconds(1)
                        connections += 1
                        NSLog("Noto live: connected (%d)", connections)
                        // A reconnect means events were missed. The first connect
                        // happens while the initial load is already running.
                        if connections > 1 { await onChange() }
                    case "pusher:ping":
                        try await socket.send(.string(#"{"event":"pusher:pong","data":{}}"#))
                    case "pusher:error":
                        // A refused key or cluster does not fix itself by retrying.
                        NSLog("Noto live: %@", text)
                        refused = true
                    case "note-deleted":
                        if let gone = Self.deleted(in: text) { await onDelete(gone.id, gone.folder) }
                    case let name? where name.hasPrefix("note-"):
                        await onChange()
                    default:
                        break
                    }
                    if refused { break }
                }
            } catch {
                // Dropped: fall through to reconnect.
            }
            keepAlive.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            if refused || Task.isCancelled { return }
            try? await Task.sleep(for: delay)
            delay = min(delay * 2, .seconds(30))
        }
    }
}
