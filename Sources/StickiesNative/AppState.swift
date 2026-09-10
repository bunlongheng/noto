import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var notes: [Note] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var query = ""
    @Published var selected: Note.ID?
    @Published var toast: String?

    let api = APIClient()

    /// Local filter on title + folder. Instant, and it covers all notes - the
    /// server's q= search reads content too but caps at 50 rows
    /// (app/api/stickies/route.ts:552), which would hide notes rather than find them.
    var visible: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(q)
            || ($0.folderName ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var selectedNote: Note? { notes.first { $0.id == selected } }

    func load() async {
        isLoading = true
        error = nil
        do { notes = try await api.fetchAllNotes() }
        catch { self.error = error.localizedDescription }
        isLoading = false
    }

    /// Move to TRASH. Not a destructive delete - the server purges trash on its own
    /// 7 day schedule, and the note stays recoverable until then.
    func trashSelected() async {
        guard let note = selectedNote else { return }
        do {
            try await api.trash(id: note.id)
            notes.removeAll { $0.id == note.id }
            selected = nil
            show("Moved to TRASH: \(note.title)")
        } catch {
            show("Could not trash it: \(error.localizedDescription)")
        }
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == message { toast = nil }
        }
    }
}
