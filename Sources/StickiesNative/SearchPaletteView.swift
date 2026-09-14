import SwiftUI

/// Centred search over every note, the way the web app's Cmd-K palette works.
///
/// The sidebar already filters the list in place, but that is browsing, not
/// jumping - and in full screen the sidebar is not even on screen. This floats
/// over whatever is open, takes a query, and lands on a note.
struct SearchPaletteView: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    /// Capped: the palette is for finding one note, and a list of 1,400 rows is
    /// not a result, it is the whole database again.
    private var results: [Note] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(state.notes.prefix(30)) }
        return Array(state.notes.lazy.filter { $0.searchKey.contains(q) }.prefix(30))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                field
                if !results.isEmpty {
                    Divider()
                    list
                } else {
                    Text("No note matches \"\(query)\"")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 22)
                }
            }
            .frame(width: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12)))
            .shadow(radius: 30, y: 12)
            .padding(.top, 110)
        }
        .onAppear { focused = true; highlighted = 0 }
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
    }

    private var field: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("Search all notes", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($focused)
                .onSubmit { open(results.indices.contains(highlighted) ? results[highlighted] : nil) }
            Text("esc")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, note in
                        row(note, active: index == highlighted)
                            .id(note.id)
                            .onTapGesture { open(note) }
                    }
                }
            }
            .frame(maxHeight: 340)
            .onChange(of: highlighted) { _, index in
                guard results.indices.contains(index) else { return }
                proxy.scrollTo(results[index].id, anchor: .center)
            }
        }
    }

    private func row(_ note: Note, active: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: NoteIcon.symbol(for: note.icon))
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(tint(note))
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let folder = note.folderName, !folder.isEmpty {
                    Text(folder).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(note.displayDate).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(active ? Color.accentColor.opacity(0.22) : .clear)
        .contentShape(Rectangle())
    }

    private func tint(_ note: Note) -> Color {
        guard let c = note.parsedColor else { return .secondary }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    private func move(_ direction: Int) {
        guard !results.isEmpty else { return }
        highlighted = (highlighted + direction + results.count) % results.count
    }

    /// Selecting a note also clears the sidebar filter - landing on a note the
    /// list is hiding would drop the selection again on the next refilter.
    private func open(_ note: Note?) {
        guard let note else { return }
        state.query = ""
        state.selected = note.id
        close()
    }

    private func close() {
        state.paletteOpen = false
    }
}
