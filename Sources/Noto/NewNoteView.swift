import SwiftUI

/// Compose a plain-text note.
///
/// Deliberately title + body only: the server files a new note under CLAUDE and
/// picks the colour and icon itself, so anything more here would just be a form
/// asking for values it is going to overwrite.
struct NewNoteView: View {
    @EnvironmentObject var state: AppState
    @State private var title = ""
    @State private var body_ = ""
    @State private var saving = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Note").font(.system(size: 15, weight: .semibold))

            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .focused($titleFocused)

            TextEditor(text: $body_)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(minHeight: 240)

            HStack {
                Spacer()
                Button("Cancel") { state.composerOpen = false }
                    .keyboardShortcut(.cancelAction)
                Button(saving ? "Creating..." : "Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(saving || body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 520)
        .onAppear { titleFocused = true }
    }

    /// The server rejects an empty body and derives a missing title from the first
    /// line, so only the body is required here.
    private func create() {
        saving = true
        Task {
            await state.createNote(title: title.trimmingCharacters(in: .whitespaces), content: body_)
            saving = false
            state.composerOpen = false
        }
    }
}
