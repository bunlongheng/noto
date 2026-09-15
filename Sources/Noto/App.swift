import AppKit
import SwiftUI

@main
struct NotoApp: App {
    @StateObject private var state = AppState()
    // Owned here, not in RootView, so the Zoom menu items can drive the same
    // web view the note is rendered in.
    @StateObject private var host = WebHost()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(state).environmentObject(host)
        }
        .defaultSize(width: 1100, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { state.composerOpen = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") { state.load() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Find in Note") { NotificationCenter.default.post(name: .focusFind, object: nil) }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Search All Notes") { state.paletteOpen = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("Zoom In") { host.zoomBy(0.1) }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { host.zoomBy(-0.1) }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { host.resetZoom() }
                    .keyboardShortcut("0", modifiers: .command)
                    .disabled(host.zoom == 1)
                Divider()
                Button("Next Tab") { state.stepTab(1) }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { state.stepTab(-1) }
                    .keyboardShortcut("[", modifiers: [.command, .shift])
                Button("Close Tab") { if let id = state.selected { state.closeTab(id) } }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                    .disabled(state.selected == nil)
                Divider()
                Button("Move to Trash") { Dust.dissolve(over: host.view) { await state.trashSelected() } }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(state.selectedNote == nil || state.selectedNote?.frozen == true)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var host: WebHost
    @State private var find = ""
    @State private var keyMonitor: Any?
    @State private var confirmingTrash = false
    @State private var confirmingEmpty = false

    var body: some View {
        NavigationSplitView {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 480)
        } detail: {
            VStack(spacing: 0) {
                // Above the note, not inside it: full screen hides the sidebar, and
                // this is what keeps every other note one click away. It stays up
                // with nothing selected too - otherwise full screen with no note
                // open has no way to reach one.
                if !state.tabs.isEmpty { TabBarView() }
                if let note = state.selectedNote {
                    NoteDetailView(note: note, host: host)
                        .onChange(of: note.id) { _, _ in find = "" }
                } else {
                    Text("Select a note")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        .task { state.load() }
        .onAppear(perform: watchKeys)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { state.composerOpen = true } label: { Image(systemName: "square.and.pencil") }
                    .help("New note (Cmd+N)")
                    .accessibilityLabel("New note")
            }
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 5) {
                    FindField(text: $find, host: host) { host.step(true) }
                        .frame(width: 170, height: 22)
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
                .disabled(state.selectedNote == nil)
                .onReceive(NotificationCenter.default.publisher(for: .focusFind)) { _ in
                    if state.selectedNote != nil { host.focusFind() }
                }
            }
            // The condition wraps the ITEMS, not their contents: an `if` inside a
            // ToolbarItem collapses to an empty item that never appears.
            if state.viewingTrash {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await state.restoreSelected() } } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(state.selectedNote == nil)
                    .help("Put this note back where it came from")
                    .accessibilityLabel("Restore note")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { confirmingEmpty = true } label: { Image(systemName: "trash.slash") }
                        .disabled(state.trashNotes.isEmpty)
                        .help("Delete everything in TRASH permanently")
                        .accessibilityLabel("Empty trash")
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                // The button asks first; Cmd+Delete does not. A click can land by
                // accident on a toolbar you were only passing through - the
                // shortcut is deliberate, and confirming it every time would be
                // noise on the gesture that exists to be fast.
                    Button { confirmingTrash = true } label: { Image(systemName: "trash") }
                        .disabled(state.selectedNote == nil || state.selectedNote?.frozen == true)
                        .help(state.selectedNote?.frozen == true
                              ? "This note is locked - unlock it in the web app"
                              : "Move to TRASH (Cmd+Delete skips this)")
                        .accessibilityLabel("Move note to trash")
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.symbol)
                        .foregroundStyle(toast.kind == .success ? .green : .orange)
                    Text(toast.text).lineLimit(2)
                    if toast.kind == .success, state.canUndoTrash {
                        Button("Undo") { Task { await state.undoTrash() } }
                            .buttonStyle(.link)
                            .keyboardShortcut("z", modifiers: .command)
                    }
                }
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
                    .shadow(radius: 8, y: 3)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.toast)
        .overlay {
            if state.paletteOpen { SearchPaletteView().transition(.opacity) }
        }
        .sheet(isPresented: $state.composerOpen) { NewNoteView() }
        .confirmationDialog(
            "Move \u{201C}\(state.selectedNote?.title ?? "")\u{201D} to TRASH?",
            isPresented: $confirmingTrash,
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) {
                Dust.dissolve(over: host.view) { await state.trashSelected() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It stays in TRASH for 7 days. Cmd+Delete skips this confirmation.")
        }
        .confirmationDialog(
            "Delete all \(state.trashNotes.count) notes in TRASH?",
            isPresented: $confirmingEmpty,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) { Task { await state.emptyTrash() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone - there is no second trash behind this one.")
        }
        .animation(.easeOut(duration: 0.12), value: state.paletteOpen)
    }

    /// Keys the menu cannot carry on its own.
    ///
    /// Plain ← / → step through the notes, but stand down while the search or
    /// find field is being typed into, so the arrows still move the caret there.
    /// Cmd +/- zoom the note: SwiftUI's keyboardShortcut("+") only ever matches
    /// the SHIFTED key, so a plain Cmd+= - what everyone actually presses - never
    /// reached the menu item. Both spellings are matched here instead.
    ///
    /// A local monitor sees the key before the web view and before the menu, and
    /// returning nil consumes it, so nothing fires twice.
    private func watchKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // The palette handles its own keys; stepping tabs behind it would move
            // the selection out from under the result the user is aiming at.
            if state.paletteOpen, flags.isEmpty { return event }

            // Cmd+Shift+F opens the palette, Cmd+F focuses the find field. keyCode 3
            // is F. The menu item alone was not enough for find: setting @FocusState
            // from the menu action left focus on the web view, so the caret never
            // arrived and whatever was typed next went nowhere. Resigning first
            // responder here is what actually frees it up.
            if event.keyCode == 3, flags == .command || flags == [.command, .shift] {
                if flags.contains(.shift) {
                    state.paletteOpen = true
                } else {
                    guard state.selectedNote != nil else { return event }
                    host.focusFind()
                }
                return nil
            }

            if flags == .command || flags == [.command, .shift] {
                switch event.charactersIgnoringModifiers {
                case "=", "+": host.zoomBy(0.1);  return nil
                case "-", "_": host.zoomBy(-0.1); return nil
                case "0":      host.resetZoom();  return nil
                default: break
                }
            }

            // Ctrl+Cmd+F. Recent macOS binds the system "Enter Full Screen" item to
            // Globe+F instead, so the shortcut every other app trained us on no
            // longer reaches the window. keyCode 3 is F; charactersIgnoringModifiers
            // comes back as a control character while Control is held.
            if flags == [.command, .control], event.keyCode == 3 {
                event.window?.toggleFullScreen(nil)
                return nil
            }

            // macOS stamps every arrow key with .function and .numericPad, so a
            // bare "no modifiers" test on the raw flags never matches.
            guard flags.isEmpty, event.keyCode == 123 || event.keyCode == 124 else { return event }
            if let responder = event.window?.firstResponder,
               responder is NSTextView || responder is NSTextField { return event }
            state.stepTab(event.keyCode == 123 ? -1 : 1)
            return nil
        }
    }
}

struct NoteListView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(state.viewingTrash ? "Trash" : "All Notes").font(.system(size: 15, weight: .semibold))
                Text(countLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                if state.isLoading { ProgressView().scaleEffect(0.5) }
                Button {
                    state.viewingTrash.toggle()
                    if state.viewingTrash { state.loadTrash() } else { state.selectFirstIfNeeded() }
                } label: {
                    Image(systemName: state.viewingTrash ? "chevron.backward" : "trash")
                }
                .buttonStyle(.plain)
                .help(state.viewingTrash ? "Back to all notes" : "Show TRASH")
                .accessibilityLabel(state.viewingTrash ? "Back to all notes" : "Show trash")
                Button { state.viewingTrash ? state.loadTrash() : state.load() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh (Cmd+R)").accessibilityLabel("Refresh notes")
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Filter by title", text: $state.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
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

            Divider()

            if let error = state.error, state.notes.isEmpty {
                message(error, systemImage: "exclamationmark.triangle", retry: true)
            } else if state.isLoading && state.notes.isEmpty {
                message("Loading notes...", systemImage: nil, retry: false)
            } else if state.notes.isEmpty {
                message("No notes", systemImage: "tray", retry: true)
            } else if state.viewingTrash && state.trashNotes.isEmpty {
                message("Trash is empty", systemImage: "trash", retry: false)
            } else if state.visible.isEmpty {
                message("No match for \"\(state.query)\"", systemImage: "magnifyingglass", retry: false)
            } else {
                // A failed refresh must not hide notes that are already loaded.
                if let error = state.error {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Refresh failed. \(error)").lineLimit(2)
                        Spacer()
                        Button("Retry") { state.load() }.buttonStyle(.link)
                    }
                    .font(.caption)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(.orange.opacity(0.12))
                }
                List(state.visible, selection: $state.selected) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                        .listRowBackground(rowBackground(note))
                }
                .listStyle(.inset)
                .background(SelectionStyler())
            }
        }
    }

    private var countLabel: String {
        let total = state.viewingTrash ? state.trashNotes.count : state.notes.count
        return state.query.isEmpty ? "\(total)" : "\(state.visible.count) of \(total)"
    }

    /// The selected row wears its own folder colour, the way the web list does -
    /// the system accent blue says nothing about which note this is.
    @ViewBuilder
    private func rowBackground(_ note: Note) -> some View {
        if state.selected == note.id {
            RoundedRectangle(cornerRadius: 6)
                .fill(rowTint(note).opacity(0.28))
                .padding(.horizontal, 4)
        } else {
            Color.clear
        }
    }

    private func rowTint(_ note: Note) -> Color {
        guard let c = note.parsedColor else { return .accentColor }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    private func message(_ text: String, systemImage: String?, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Spacer()
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 28)).foregroundStyle(.secondary)
            }
            Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)
            if retry { Button("Try again") { state.load() } }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteRow: View {
    let note: Note

    // Tight on purpose: every point the trailing columns give back is a point of
    // title the row can show before it truncates.
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: NoteIcon.symbol(for: note.icon))
                .font(.system(size: 13))
                .frame(width: 16)
                .foregroundStyle(tint)

            // Title only. The folder used to sit under it, which cost every row a
            // second line for something the icon's colour already carries.
            Text(note.title).font(.system(size: 13)).lineLimit(1)

            Spacer(minLength: 6)

            // Fixed columns, not a ragged trailing run: a row with no badges must not
            // slide its submitter icon and date out of line with the row above it.
            // Share state reads the same as the web app - a globe is public, a teal
            // lock is passcode-gated, an amber lock is write-protected, and THAT one
            // is the note the server will refuse to trash.
            // Only the rows that HAVE a badge pay for the lane. Reserving it on every
            // row cost ~30pt of title on the 95% of notes that are neither shared nor
            // locked; the submitter icon and date stay aligned regardless, because
            // they are anchored to the trailing edge, not to this.
            if note.isPublic == true || note.locked == true || note.frozen == true {
                HStack(spacing: 3) {
                    if note.isPublic == true, note.locked != true {
                        badge("globe", .green, "Public - anyone with the link")
                    }
                    if note.locked == true {
                        badge("lock", Color(nsColor: .systemTeal), "Private - passcode to view")
                    }
                    if note.frozen == true {
                        badge("lock.fill", .orange, "Locked - cannot be edited or trashed")
                    }
                }
            }

            SubmitterBadge(note: note)

            // In TRASH the date that matters is the deadline, not the creation time:
            // the server purges on its own 7 day schedule.
            if let days = note.daysLeft {
                Text(days > 0 ? "\(days)d left" : "expiring")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(days <= 1 ? .red : .orange)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text(note.displayDate)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func badge(_ symbol: String, _ color: Color, _ help: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .help(help)
            .accessibilityLabel(help)
    }

    /// Keep the folder colour the dot used to carry - now it tints the icon.
    private var tint: Color {
        guard let c = note.parsedColor else { return .secondary }
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

/// SwiftUI paints List selection with the system accent and gives no way to change
/// it, so the AppKit table underneath is told not to draw a highlight at all and
/// each row paints its own - see `rowBackground`.
struct SelectionStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ view: NSView, context: Context) {
        // Deferred: the view is not in the hierarchy yet when this first runs.
        // NSOutlineView is an NSTableView, so the one cast covers both.
        DispatchQueue.main.async {
            var next: NSView? = view.superview
            while let current = next {
                if let table = current.descendantTable() {
                    table.selectionHighlightStyle = .none
                    return
                }
                next = current.superview
            }
        }
    }
}

private extension NSView {
    /// The first table view at or below this view.
    func descendantTable() -> NSTableView? {
        if let table = self as? NSTableView { return table }
        for child in subviews {
            if let found = child.descendantTable() { return found }
        }
        return nil
    }
}

/// Who posted the note, as the web list shows it: the posting app's icon, the
/// device's, or the owner's avatar. Served by the notes app, so it is the same
/// artwork both places. An unknown key has no icon file - that falls back to a
/// initials chip rather than a broken image.
struct SubmitterBadge: View {
    let note: Note

    var body: some View {
        AsyncImage(url: note.submitterIconURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 3))
            case .failure:
                Text(note.submitterInitials)
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
            case .empty:
                Color.clear
            @unknown default:
                Color.clear
            }
        }
        .frame(width: 16, height: 16)
        .help(note.createdByKey ?? note.createdByMachine ?? "Created in the notes app")
    }
}
