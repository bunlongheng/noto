import SwiftUI

@main
struct StickiesNativeApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            NoteListView()
                .environmentObject(state)
                .frame(minWidth: 460, minHeight: 400)
                .task { await state.load() }
        }
        .defaultSize(width: 620, height: 780)
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

    private let api = APIClient()

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
            } else {
                List(state.notes) { NoteRow(note: $0) }
                    .listStyle(.inset)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("All Notes")
                .font(.system(size: 15, weight: .semibold))
            Text("\(state.notes.count)")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
