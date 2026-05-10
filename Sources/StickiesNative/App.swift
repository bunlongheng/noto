import SwiftUI

@main
struct StickiesNativeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    ContentView()
                        .environmentObject(appState)
                        .frame(minWidth: 900, minHeight: 600)
                } else {
                    LoginView()
                        .environmentObject(authManager)
                        .frame(width: 400, height: 480)
                }
            }
            .environmentObject(authManager)
            .onOpenURL { url in
                Task { await authManager.handleCallback(url: url) }
            }
            .onChange(of: authManager.accessToken) {
                if let token = authManager.accessToken {
                    appState.apiClient.setToken(token)
                    Task { await appState.loadNotes() }
                }
            }
            .onAppear {
                if let token = authManager.accessToken {
                    appState.apiClient.setToken(token)
                }
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
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
