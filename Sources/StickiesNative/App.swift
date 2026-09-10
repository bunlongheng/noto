import SwiftUI

@main
struct StickiesNativeApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(state)
        }
        .defaultSize(width: 1100, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) { }   // read-mostly app, no New
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await state.load() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Find in Note") { NotificationCenter.default.post(name: .focusFind, object: nil) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Search Notes") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("Move to Trash") { Task { await state.trashSelected() } }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(state.selectedNote == nil)
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

struct RootView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var host = WebHost()
    @State private var find = ""
    @FocusState private var findFocused: Bool

    var body: some View {
        NavigationSplitView {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
        } detail: {
            if let note = state.selectedNote {
                NoteDetailView(note: note, host: host)
                    .onChange(of: note.id) { _, _ in find = "" }
            } else {
                Text("Select a note")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .task { await state.load() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 5) {
                    Image(systemName: "text.magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Find in note", text: $find)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .frame(width: 150)
                        .focused($findFocused)
                        .onSubmit { host.step(true) }
                        .onChange(of: find) { _, new in host.find(new) }
                    if !find.isEmpty {
                        Text(host.matches == 0 ? "none" : "\(host.current)/\(host.matches)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(host.matches == 0 ? .orange : .secondary)
                        Button { host.step(false) } label: { Image(systemName: "chevron.up").font(.system(size: 10)) }
                            .buttonStyle(.plain).disabled(host.matches == 0).accessibilityLabel("Previous match")
                        Button { host.step(true) } label: { Image(systemName: "chevron.down").font(.system(size: 10)) }
                            .buttonStyle(.plain).disabled(host.matches == 0).accessibilityLabel("Next match")
                        Button { find = ""; host.clear() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear find")
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(state.selectedNote == nil)
                .onReceive(NotificationCenter.default.publisher(for: .focusFind)) { _ in
                    if state.selectedNote != nil { findFocused = true }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await state.trashSelected() } } label: { Image(systemName: "trash") }
                    .disabled(state.selectedNote == nil)
                    .help("Move to TRASH (Cmd+Delete)")
                    .accessibilityLabel("Move note to trash")
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .shadow(radius: 8, y: 3)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.toast)
    }
}

struct NoteListView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("All Notes").font(.system(size: 15, weight: .semibold))
                Text(state.query.isEmpty ? "\(state.notes.count)" : "\(state.visible.count) of \(state.notes.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                if state.isLoading { ProgressView().scaleEffect(0.5) }
                Button { Task { await state.load() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh (Cmd+R)").accessibilityLabel("Refresh notes")
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search all notes", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searchFocused)
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in searchFocused = true }

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

    private func message(_ text: String, systemImage: String?, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Spacer()
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 28)).foregroundStyle(.secondary)
            }
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            if retry { Button("Try again") { Task { await state.load() } } }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: NoteIcon.symbol(for: note.icon))
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let folder = note.folderName, !folder.isEmpty {
                    Text(folder).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(note.displayDate).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// Keep the folder colour the dot used to carry - now it tints the icon.
    private var tint: Color {
        guard let c = note.parsedColor else { return .secondary }
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}
