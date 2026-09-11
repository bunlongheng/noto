import SwiftUI

/// What the toast is reporting. Success and failure looked identical before, and
/// neither was announced to VoiceOver.
struct Toast: Equatable {
    enum Kind { case success, failure }
    let kind: Kind
    let text: String
    var symbol: String { kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill" }
}

/// A note that was just moved to TRASH, kept so the move can be undone.
private struct Trashed {
    let note: Note
    let index: Int
    let folder: String?
}

@MainActor
final class AppState: ObservableObject {
    @Published var notes: [Note] = [] { didSet { refilter() } }
    @Published var isLoading = false
    @Published var error: String?
    @Published var query = "" { didSet { refilter() } }
    @Published var selected: Note.ID?
    @Published var toast: Toast?
    @Published var loadedCount: Int?

    /// Recomputed only when notes or the query change. As a computed property this
    /// ran three times per body evaluation, on every published change.
    @Published private(set) var visible: [Note] = []

    private let api = APIClient()
    private var loadTask: Task<Void, Never>?
    private var lastTrashed: Trashed?
    private let bodies = NSCache<NSString, NSString>()

    init() { bodies.totalCostLimit = 50 * 1024 * 1024 }

    var selectedNote: Note? { notes.first { $0.id == selected } }

    private func refilter() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        visible = q.isEmpty ? notes : notes.filter { $0.searchKey.contains(q) }
        // Selection could otherwise point at a note the filter hides, leaving the
        // detail pane and Cmd+Delete acting on something not on screen.
        if let s = selected, !visible.contains(where: { $0.id == s }) { selected = nil }
    }

    /// Reload the list. Pages are shown as they arrive rather than after the whole
    /// crawl, and a concurrent call replaces the one in flight instead of racing it.
    func load() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            isLoading = true
            error = nil
            do {
                let all = try await api.fetchAllNotes { [weak self] page, total in
                    self?.notes = page
                    self?.loadedCount = total
                }
                notes = all
            } catch is CancellationError {
                // Superseded by a newer load.
            } catch {
                // Keep whatever already arrived; a failed page must not blank the list.
                self.error = error.localizedDescription
            }
            isLoading = false
            loadTask = nil
        }
        // Callers await nothing; the task owns its own lifetime.
    }

    /// The body of a note, cached by id and revision so re-selecting is instant.
    func body(for note: Note) async throws -> String {
        let key = "\(note.id)|\(note.updatedAt ?? "")" as NSString
        if let hit = bodies.object(forKey: key) { return hit as String }
        let fetched = try await api.fetchNote(id: note.id).content ?? ""
        bodies.setObject(fetched as NSString, forKey: key, cost: fetched.utf8.count)
        return fetched
    }

    /// Move to TRASH. Not a destructive delete - the server purges trash on its own
    /// 7 day schedule, and `undoTrash` puts it back until then.
    func trashSelected() async {
        guard let note = selectedNote, let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        do {
            try await api.trash(id: note.id)
            lastTrashed = Trashed(note: note, index: index, folder: note.folderName)
            notes.remove(at: index)
            // Land on a neighbour rather than dumping the user out of the list.
            selected = visible.indices.contains(index) ? visible[index].id
                     : visible.indices.contains(index - 1) ? visible[index - 1].id : nil
            show(.success, "Moved to TRASH: \(note.title)")
        } catch {
            show(.failure, "Could not trash it: \(error.localizedDescription)")
        }
    }

    var canUndoTrash: Bool { lastTrashed != nil }

    func undoTrash() async {
        guard let last = lastTrashed else { return }
        do {
            try await api.restore(id: last.note.id, toFolder: last.folder)
            notes.insert(last.note, at: min(last.index, notes.count))
            selected = last.note.id
            lastTrashed = nil
            show(.success, "Restored: \(last.note.title)")
        } catch {
            show(.failure, "Could not restore it: \(error.localizedDescription)")
        }
    }

    private func show(_ kind: Toast.Kind, _ message: String) {
        let t = Toast(kind: kind, text: message)
        toast = t
        AccessibilityNotification.Announcement(message).post()
        Task {
            try? await Task.sleep(for: .seconds(5))
            if toast == t { toast = nil }
        }
    }
}
