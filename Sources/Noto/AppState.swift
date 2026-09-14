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
    /// The centred search palette. Lives here rather than in RootView so the menu
    /// command can open it too.
    @Published var paletteOpen = false
    @Published var loadedCount: Int?

    /// Recomputed only when notes or the query change. As a computed property this
    /// ran three times per body evaluation, on every published change.
    @Published private(set) var visible: [Note] = []

    /// The tab strip mirrors the visible list, minus the tabs the user closed -
    /// the same rule the web app uses. Closing has to be remembered here or the
    /// next refilter brings the tab straight back.
    @Published private(set) var tabs: [Note] = []
    private var dismissed: Set<Note.ID> = []

    private let api = APIClient()
    private var loadTask: Task<Void, Never>?
    private var lastTrashed: Trashed?
    private let bodies = NSCache<NSString, NSString>()

    init() { bodies.totalCostLimit = 50 * 1024 * 1024 }

    var selectedNote: Note? { notes.first { $0.id == selected } }

    private func refilter() {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        visible = q.isEmpty ? notes : notes.filter { $0.searchKey.contains(q) }
        tabs = dismissed.isEmpty ? visible : visible.filter { !dismissed.contains($0.id) }
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

    /// Close a tab. The note itself is untouched - this only hides it from the
    /// strip - and the neighbour that slides into the slot becomes active so the
    /// detail pane never goes blank.
    func closeTab(_ id: Note.ID) {
        let index = tabs.firstIndex { $0.id == id }
        dismissed.insert(id)
        refilter()
        guard selected == id else { return }
        guard let index, !tabs.isEmpty else { selected = nil; return }
        selected = tabs[min(index, tabs.count - 1)].id
    }

    /// Flip to the next or previous tab, wrapping at either end.
    func stepTab(_ direction: Int) {
        guard !tabs.isEmpty else { return }
        guard let current = tabs.firstIndex(where: { $0.id == selected }) else {
            selected = tabs[0].id
            return
        }
        selected = tabs[(current + direction + tabs.count) % tabs.count].id
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
