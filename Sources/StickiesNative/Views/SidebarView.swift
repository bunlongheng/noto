import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("appThemeMode") private var themeMode: ThemeMode = .auto
    @State private var showNewNote = false
    @State private var newTitle = ""
    @State private var newFolder = "CLAUDE"

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search notes...", text: $appState.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !appState.searchText.isEmpty {
                    Button {
                        appState.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Notes list
            if appState.isLoading && appState.notes.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading notes...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else {
                List(appState.filteredNotes, selection: $appState.selectedNoteId) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                }
                .listStyle(.sidebar)
            }

            Divider()

            // Bottom toolbar
            HStack {
                Button {
                    showNewNote = true
                } label: {
                    Label("New Note", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Button {
                    Task { await appState.loadNotes() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(appState.isLoading)

                Text("\(appState.notes.count) notes")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button {
                    switch themeMode {
                    case .auto: themeMode = .light
                    case .light: themeMode = .dark
                    case .dark: themeMode = .auto
                    }
                } label: {
                    Image(systemName: themeMode == .light ? "sun.max.fill" : themeMode == .dark ? "moon.fill" : "circle.lefthalf.filled")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Theme: \(themeMode.rawValue)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .sheet(isPresented: $showNewNote) {
            newNoteSheet
        }
    }

    private var newNoteSheet: some View {
        VStack(spacing: 16) {
            Text("New Note")
                .font(.headline)

            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Folder", text: $newFolder)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    showNewNote = false
                    newTitle = ""
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Create") {
                    guard !newTitle.isEmpty else { return }
                    Task {
                        await appState.createNote(
                            title: newTitle,
                            content: "",
                            folderName: newFolder
                        )
                        newTitle = ""
                        showNewNote = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newTitle.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let color = note.parsedColor {
                    Circle()
                        .fill(Color(red: color.r, green: color.g, blue: color.b))
                        .frame(width: 8, height: 8)
                }
                Text(note.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }

            HStack(spacing: 4) {
                if let folder = note.folderName {
                    Text(folder)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(3)
                }

                Spacer()

                Text(note.displayDate)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
