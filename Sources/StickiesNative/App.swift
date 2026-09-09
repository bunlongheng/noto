import SwiftUI

@main
struct StickiesNativeApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                NoteListView()
                    .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
            } detail: {
                if let id = state.selected, let note = state.notes.first(where: { $0.id == id }) {
                    NoteDetailView(note: note)
                } else {
                    Text("Select a note")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .environmentObject(state)
            .frame(minWidth: 760, minHeight: 420)
            .task { await state.load() }
        }
        .defaultSize(width: 1100, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) { }   // read-only app, no New
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await state.load() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var notes: [Note] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var query = ""
    @Published var selected: Note.ID?

    let api = APIClient()

    /// Local filter on title + folder. Instant, and it covers all 1,386 notes -
    /// the server's q= search reads content too but is capped at 50 rows
    /// (app/api/stickies/route.ts:552), which would hide notes rather than find them.
    var visible: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(q)
            || ($0.folderName ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            notes = try await api.fetchAllNotes()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct NoteListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let error = state.error {
                message(error, systemImage: "exclamationmark.triangle", retry: true)
            } else if state.isLoading && state.notes.isEmpty {
                message("Loading notes...", systemImage: nil, retry: false)
            } else if state.notes.isEmpty {
                message("No notes", systemImage: "tray", retry: true)
            } else if state.visible.isEmpty {
                message("No match for \"\(state.query)\"", systemImage: "magnifyingglass", retry: false)
            } else {
                List(state.visible, selection: $state.selected) { note in
                    NoteRow(note: note).tag(note.id)
                }
                .listStyle(.inset)
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
        HStack(spacing: 8) {
            Text("All Notes")
                .font(.system(size: 15, weight: .semibold))
            Text(state.query.isEmpty ? "\(state.notes.count)" : "\(state.visible.count) of \(state.notes.count)")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
            Spacer()
            if state.isLoading { ProgressView().scaleEffect(0.5) }
            Button { Task { await state.load() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh (Cmd+R)")
            .accessibilityLabel("Refresh notes")
        }
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search title or folder", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !state.query.isEmpty {
                Button { state.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func message(_ text: String, systemImage: String?, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Spacer()
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            if retry {
                Button("Try again") { Task { await state.load() } }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let folder = note.folderName, !folder.isEmpty {
                    Text(folder)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(note.displayDate)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var dotColor: Color {
        guard let c = note.parsedColor else { return .secondary.opacity(0.4) }
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}
