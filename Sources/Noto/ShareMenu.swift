import SwiftUI

/// The share controls, reading and writing the same three flags the web app's
/// share sheet does: public, passcode-gated, and write-protected.
///
/// These go out on the owner path, not the API key - the server strips share
/// fields from any keyed request, so this is the only way they can move from here.
struct ShareMenu: View {
    @EnvironmentObject var state: AppState
    @Binding var passcodeSheet: Bool
    @Binding var inviteSheet: Bool

    var body: some View {
        Menu {
            if let note = state.selectedNote {
                Toggle("Public", isOn: Binding(
                    get: { note.isPublic == true },
                    set: { on in Task { await state.setPublic(on) } }))
                    .help("Anyone with the link can view")

                // Turning it ON needs a passcode first, so it opens the sheet;
                // turning it OFF is immediate, the way the web toggle behaves.
                Toggle("Private - passcode", isOn: Binding(
                    get: { note.locked == true },
                    set: { on in
                        if on { passcodeSheet = true }
                        else { Task { await state.setPrivate(false, passcode: "") } }
                    }))
                    .help("Gate the share link behind a passcode")

                Toggle("Locked - no edits", isOn: Binding(
                    get: { note.frozen == true },
                    set: { on in Task { await state.setFrozen(on) } }))
                    .help("Write-protect: the server refuses edits and the trash move")

                // Same rule as the web Share modal: invites only apply to a passcode-gated link.
                Button("Invite...") { inviteSheet = true }
                    .disabled(note.locked != true)
                    .help("Let an email open the private link without the passcode")

                Divider()
                Button("Copy Link") {
                    // A link to an unpublished note resolves to nothing, so publish
                    // first - the same thing the web Copy button does.
                    if note.isPublic != true { Task { await state.setPublic(true) } }
                    else { state.copy(state.shareURL(for: note), as: "Link copied") }
                }
                Button("Copy curl Command") {
                    if note.isPublic != true { Task { await state.setPublic(true) } }
                    state.copy("curl -s \"\(state.shareURL(for: note))\"", as: "curl command copied")
                }
                Button("Open in Browser") {
                    if let url = URL(string: state.shareURL(for: note)) { NSWorkspace.shared.open(url) }
                }
            }
        } label: {
            Image(systemName: symbol)
        }
        .disabled(state.selectedNote == nil)
        .help("Share this note")
        .accessibilityLabel("Share")
    }

    /// The same glyph the row badge shows, so the toolbar says the note's share
    /// state without opening the menu.
    private var symbol: String {
        guard let note = state.selectedNote else { return "square.and.arrow.up" }
        if note.frozen == true { return "lock.fill" }
        if note.locked == true { return "key.fill" }
        if note.isPublic == true { return "globe" }
        return "square.and.arrow.up"
    }
}

/// Asks for the passcode that gates a Private share. Blank is allowed and means
/// "shared, no gate" - the same answer an empty prompt gives in the web app.
struct PasscodeSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var passcode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Passcode for the share link").font(.headline)
            Text("Leave it blank to share without a passcode.")
                .font(.caption).foregroundStyle(.secondary)
            SecureField("Passcode", text: $passcode)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Lock") {
                    let entered = passcode.trimmingCharacters(in: .whitespaces)
                    Task { await state.setPrivate(true, passcode: entered) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

/// Who may open a Private note's link without the passcode. Calls the same
/// /api/stickies/invites route as the web Share modal, which emails the invite.
struct InviteSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var invited: [String] = []
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invite").font(.headline)
            Text("Invited people sign in with their email and a password they pick - no passcode.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(invited, id: \.self) { address in
                HStack {
                    Text(address)
                    Spacer()
                    Button { Task { await remove(address) } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(address)")
                }
            }
            HStack {
                TextField("name@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await add() } }
                Button("Invite") { Task { await add() } }
                    .disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 340)
        .task { if let id = state.selectedNote?.id { invited = (try? await state.invites(noteId: id)) ?? [] } }
    }

    private func add() async {
        guard let id = state.selectedNote?.id else { return }
        let address = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !address.isEmpty else { return }
        busy = true; defer { busy = false }
        if let list = await state.invite(noteId: id, email: address) { invited = list; email = "" }
    }

    private func remove(_ address: String) async {
        guard let id = state.selectedNote?.id else { return }
        if let list = await state.uninvite(noteId: id, email: address) { invited = list }
    }
}
