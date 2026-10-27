import SwiftUI

/// Hashtags in the note's bottom right corner: a chip per tag, an x to drop one,
/// and a field that opens on + so several can be typed in a row. Tinted with the
/// folder colour so the chips read as part of the note.
struct TagBar: View {
    let note: Note
    /// The pointer is over the note: an empty bar only appears then, a full one goes opaque.
    var hovering = false
    @EnvironmentObject var state: AppState
    @State private var adding = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var tags: [String] { state.tags[note.id] ?? note.tags ?? [] }
    private var editable: Bool { note.frozen != true }
    private var tint: Color {
        guard let c = note.parsedColor else { return .accentColor }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    var body: some View {
        if tags.isEmpty && !hovering && !adding {
            EmptyView()
        } else {
            bar.opacity(hovering || adding ? 1 : 0.25)
                .animation(.easeOut(duration: 0.2), value: hovering)
        }
    }

    private var bar: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 4) {
                    Text("#" + tag)
                    if editable {
                        Button { save(tags.filter { $0 != tag }) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                        }
                        .buttonStyle(.plain).opacity(0.55)
                        .help("Remove #\(tag)")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(tint.opacity(0.14), in: Capsule())
            }
            if adding {
                TextField("tag", text: $draft)
                    .textFieldStyle(.plain).font(.caption)
                    .frame(width: 90)
                    .focused($focused)
                    .onAppear { focused = true }
                    .onSubmit { commit() }
                    .onExitCommand { adding = false; draft = "" }
                    .onChange(of: focused) { if !focused { adding = false } }
            } else if editable {
                Button { adding = true } label: {
                    Image(systemName: tags.isEmpty ? "number" : "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add a hashtag")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .padding(14)
        .animation(.spring(duration: 0.25, bounce: 0.3), value: tags)
    }

    /// "#Vincent, kactus" becomes vincent and kactus; what is already there stays once.
    private func commit() {
        let typed = draft.split { $0 == " " || $0 == "," }
            .map { $0.drop { $0 == "#" }.lowercased() }
            .filter { !$0.isEmpty }
        draft = ""
        var merged = tags
        for t in typed where !merged.contains(t) { merged.append(t) }
        if merged != tags { save(merged) }
    }

    private func save(_ new: [String]) { Task { await state.setTags(new, for: note) } }
}
