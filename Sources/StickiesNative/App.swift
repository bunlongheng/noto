import SwiftUI

@main
struct StickiesNativeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager()
    @AppStorage("appThemeMode") private var themeMode: ThemeMode = .auto

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authManager)
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(themeMode.colorScheme)
                .onAppear {
                    appState.apiClient.setToken(Config.localApiKey)
                    Task { await appState.loadNotes() }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .appSettings) {
                Menu("Theme") {
                    Button("Auto") { themeMode = .auto }
                    Button("Light") { themeMode = .light }
                    Button("Dark") { themeMode = .dark }
                }
            }
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selectedNoteId: String?
    @Published var isLoading = false
    @Published var searchText = ""
    @Published var errorMessage: String?

    let apiClient = APIClient()

    var filteredNotes: [Note] {
        if searchText.isEmpty {
            return notes
        }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(searchText) ||
            (note.folderName ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var selectedNote: Note? {
        guard let id = selectedNoteId else { return nil }
        return notes.first { $0.id == id }
    }

    func loadNotes() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await apiClient.fetchNotes()
            notes = fetched
            if selectedNoteId == nil, let first = fetched.first {
                selectedNoteId = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadNoteContent(id: String) async -> String? {
        do {
            let note = try await apiClient.fetchNote(id: id)
            if let idx = notes.firstIndex(where: { $0.id == id }) {
                notes[idx].content = note.content
            }
            return note.content
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateNote(id: String, content: String) async {
        do {
            try await apiClient.updateNote(id: id, content: content)
            if let idx = notes.firstIndex(where: { $0.id == id }) {
                notes[idx].content = content
                notes[idx].updatedAt = ISO8601DateFormatter().string(from: Date())
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createNote(title: String, content: String, folderName: String) async {
        do {
            let note = try await apiClient.createNote(title: title, content: content, folderName: folderName)
            notes.insert(note, at: 0)
            selectedNoteId = note.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum ThemeMode: String {
    case auto, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
