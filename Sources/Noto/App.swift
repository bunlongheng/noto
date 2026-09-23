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
                Button("Save Note as PNG...") { saveImage(.png) }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(state.selectedNote == nil)
                if NoteExport.webpEncoder != nil {
                    Button("Save Note as WebP...") { saveImage(.webp) }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        .disabled(state.selectedNote == nil)
                }
                Divider()
                Button("Move to Trash") { Dust.dissolve(over: host.view) { await state.trashSelected() } }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(state.selectedNote == nil || state.selectedNote?.frozen == true)
            }
        }
    }

    /// One path for both the menu item and the toolbar item. A cancelled save
    /// panel comes back with an empty message, which is not worth a toast.
    private func saveImage(_ format: NoteExport.Format) {
        guard let note = state.selectedNote else { return }
        Task {
            let (kind, message) = await NoteExport.save(note: note.title, from: host.view, format: format)
            if !message.isEmpty { state.show(kind, message) }
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
    @State private var findBarOpen = false
    /// Tracked so the footer can appear only once the sidebar is gone - with it
    /// open, the list row already says who posted the note and when.
    @State private var columns: NavigationSplitViewVisibility = .all
    /// The width to come back to, so widening lands where the list was.
    @State private var wideWidth: CGFloat = 320

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            NoteListView()
                // 44 is the icon-only floor - the divider drags freely anywhere
                // between that and 480, and the list re-lays itself out as it goes.
                .navigationSplitViewColumnWidth(min: 44, ideal: 320, max: 480)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: cycleWidth) {
                            Image(systemName: "arrow.left.to.line.compact")
                        }
                        .help("Squeeze the list: narrow, then icons, then back")
                        .accessibilityLabel("Narrow note list")
                    }
                }
        } detail: {
            VStack(spacing: 0) {
                // Above the note, not inside it: full screen hides the sidebar, and
                // this is what keeps every other note one click away. It stays up
                // with nothing selected too - otherwise full screen with no note
                // open has no way to reach one.
                if !state.tabs.isEmpty { TabBarView() }
                if let note = state.selectedNote {
                    NoteDetailView(note: note, host: host)
                        .onChange(of: note.id) { _, _ in closeFind() }
                        // Over the note, not in the toolbar. As a toolbar item the
                        // field was the first thing macOS pushed into the overflow
                        // chevron on a narrower window, so Cmd+F focused a field
                        // that was not on screen. Here it cannot be collapsed away.
                        .overlay(alignment: .topTrailing) {
                            if findBarOpen { findBar }
                        }
                        .overlay(alignment: .bottomLeading) { SubmitterChip(note: note) }
                        // Top centre: the find bar owns the top right and the
                        // submitter chip the bottom left, so this lands on the one
                        // edge nothing else uses.
                        .overlay(alignment: .top) {
                            if host.showingZoom { zoomBadge }
                        }
                        .animation(.easeOut(duration: 0.18), value: host.showingZoom)
                        .animation(.easeOut(duration: 0.18), value: host.zoom)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            if columns == .detailOnly { NoteFooter(note: note) }
                        }
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
        .onReceive(NotificationCenter.default.publisher(for: .focusFind)) { _ in openFind() }
        .animation(.easeOut(duration: 0.15), value: findBarOpen)
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
            // A plain button when PNG is the only thing this Mac can write, a menu
            // when cwebp is installed - a one-item menu is a worse button.
            ToolbarItem(placement: .primaryAction) {
                Group {
                    if NoteExport.webpEncoder == nil {
                        Button { saveImage(.png) } label: { Image(systemName: "square.and.arrow.down") }
                    } else {
                        Menu {
                            Button("PNG") { saveImage(.png) }
                            Button("WebP") { saveImage(.webp) }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                }
                .disabled(state.selectedNote == nil)
                .help("Save the whole note as an image (Cmd+S)")
                .accessibilityLabel("Save note as image")
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

    /// The zoom level, shown for a beat after every Cmd +/-/0 and then gone. It
    /// reads 100% on Actual Size too, so the reset lands with the same confirmation
    /// every other zoom gets.
    private var zoomBadge: some View {
        HStack(spacing: 7) {
            Image(systemName: host.zoom > 1 ? "plus.magnifyingglass"
                            : host.zoom < 1 ? "minus.magnifyingglass"
                            : "1.magnifyingglass")
                .foregroundStyle(.white.opacity(0.65))
            Text("\(Int((host.zoom * 100).rounded()))%")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 8)
        // A fixed dark HUD, not a material: the note itself is a web page with its
        // own white background, so a material tinted by the app appearance came out
        // grey text on grey over white content.
        .background(Color.black.opacity(0.78), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 3)
        .padding(.top, 16)
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .offset(y: -8)))
        .accessibilityLabel("Zoom \(Int((host.zoom * 100).rounded())) percent")
    }

    /// Find in note, floating over the page - field, live counter, step buttons.
    private var findBar: some View {
        HStack(spacing: 6) {
            // No magnifier of our own: FindField is an NSSearchField and draws one.
            FindField(text: $find, host: host) { host.step(true) }
                .frame(width: 180, height: 18)
                .onChange(of: find) { _, new in host.find(new) }
            if !find.isEmpty {
                Text(host.matches == 0 ? "none" : "\(host.current)/\(host.matches)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(host.matches == 0 ? .orange : .secondary)
            }
            Button { host.step(false) } label: { Image(systemName: "chevron.up").font(.system(size: 10)) }
                .buttonStyle(.plain).disabled(host.matches == 0).accessibilityLabel("Previous match")
            Button { host.step(true) } label: { Image(systemName: "chevron.down").font(.system(size: 10)) }
                .buttonStyle(.plain).disabled(host.matches == 0).accessibilityLabel("Next match")
            Button { closeFind() } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close find")
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12)))
        .shadow(radius: 10, y: 3)
        .padding(10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Open the bar and put the caret in it. The field only exists once the bar is
    /// on screen, so focusing has to wait a beat for SwiftUI to build it.
    private func openFind() {
        guard state.selectedNote != nil else { return }
        findBarOpen = true
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            host.focusFind()
        }
    }

    private func closeFind() {
        findBarOpen = false
        find = ""
        host.clear()
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
    /// The toolbar's copy of the File menu item. Same call, same toast.
    private func saveImage(_ format: NoteExport.Format) {
        guard let note = state.selectedNote else { return }
        Task {
            let (kind, message) = await NoteExport.save(note: note.title, from: host.view, format: format)
            if !message.isEmpty { state.show(kind, message) }
        }
    }

    /// Moving the real divider, not the column-width modifier: setting min == max
    /// narrows the split but leaves the sidebar's content laid out at the old
    /// width and clipped at its leading edge. A divider move is what a drag does.
    ///
    /// One click walks down the same three stops a drag can land on by hand -
    /// full, narrow, icons - and the fourth click returns to the width you came
    /// from. Dragging is never overridden: nothing snaps a hand-set width back.
    private func cycleWidth() {
        let windows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.windows
        guard let split = windows.lazy.compactMap({ Self.splitView(in: $0.contentView) }).first else { return }
        let current = split.subviews.first?.frame.width ?? 320
        let next: CGFloat
        if current > 260 {
            wideWidth = current
            next = 150
        } else if current > 110 {
            next = 44
        } else {
            next = wideWidth
        }
        split.setPosition(next, ofDividerAt: 0)
    }

    private static func splitView(in view: NSView?) -> NSSplitView? {
        guard let view else { return nil }
        if let split = view as? NSSplitView, split.subviews.count > 1 { return split }
        for child in view.subviews {
            if let found = splitView(in: child) { return found }
        }
        return nil
    }

    private func watchKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // The palette handles its own keys; stepping tabs behind it would move
            // the selection out from under the result the user is aiming at.
            if state.paletteOpen, flags.isEmpty { return event }

            // Escape closes the find bar, wherever the caret is.
            if flags.isEmpty, event.keyCode == 53, findBarOpen {
                closeFind()
                return nil
            }

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
                    openFind()
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

/// How much of a row there is room to draw. Read from the real width every frame,
/// so a hand-drag of the divider changes the layout as it moves - no snapping, and
/// no separate "compact mode" the width can disagree with.
enum ListDensity {
    case full    // icon, title, badges, submitter, date
    case narrow  // icon and title
    case icons   // icon only

    init(width: CGFloat) {
        if width < 110 { self = .icons } else if width < 260 { self = .narrow } else { self = .full }
    }
}

struct NoteListView: View {
    @EnvironmentObject var state: AppState
    @State private var width: CGFloat = 320

    private var density: ListDensity { ListDensity(width: width) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // At icon width there is no room for either, and a clipped "All
                // Not..." says less than the icons below it.
                if density != .icons {
                    Text(state.viewingTrash ? "Trash" : "All Notes").font(.system(size: 12, weight: .semibold))
                        .lineLimit(1).fixedSize()
                    Text(countLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                if state.isLoading && density != .icons { ProgressView().scaleEffect(0.5) }
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
            .padding(.horizontal, density == .icons ? 6 : 10)
            .padding(.top, 10).padding(.bottom, 6)

            // A text field 30pt wide is not a text field. At icon width the row
            // becomes the button that opens the full search instead.
            if density == .icons {
                Button { state.paletteOpen = true } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 12))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Search all notes (Cmd+Shift+F)")
                .accessibilityLabel("Search all notes")
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                    FilterField(text: $state.query) { state.stepSelection($0) }
                        .frame(height: 16)
                    if !state.query.isEmpty {
                        Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)) }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

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
                ScrollViewReader { proxy in
                    List(state.visible, selection: $state.selected) { note in
                        NoteRow(note: note, density: density)
                            .tag(note.id)
                            .listRowBackground(rowBackground(note))
                    }
                    .listStyle(.inset)
                    .background(SelectionStyler())
                    // Arrow-stepping past the bottom of the window would otherwise
                    // move a selection nobody can see.
                    .onChange(of: state.selected) { _, id in
                        guard let id else { return }
                        proxy.scrollTo(id)
                    }
                }
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, w in width = w }
            }
        )
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
    var density: ListDensity = .full

    // Tight on purpose: every point the trailing columns give back is a point of
    // title the row can show before it truncates.
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: NoteIcon.symbol(for: note.icon))
                .font(.system(size: 13))
                .frame(width: 16)
                .foregroundStyle(tint)
                // The icon is the whole row now, so it has to carry the title the
                // row can no longer show.
                .help(density == .icons ? note.title : "")

            // Title only. The folder used to sit under it, which cost every row a
            // second line for something the icon's colour already carries.
            if density != .icons {
                Text(note.title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
            }

            Spacer(minLength: density == .icons ? 0 : 6)

            // Fixed columns, not a ragged trailing run: a row with no badges must not
            // slide its submitter icon and date out of line with the row above it.
            // Share state reads the same as the web app - a globe is public, a teal
            // lock is passcode-gated, an amber lock is write-protected, and THAT one
            // is the note the server will refuse to trash.
            // Only the rows that HAVE a badge pay for the lane. Reserving it on every
            // row cost ~30pt of title on the 95% of notes that are neither shared nor
            // locked; the submitter icon and date stay aligned regardless, because
            // they are anchored to the trailing edge, not to this.
            // One status glyph, never two locks: LOCK means write-protected, KEY
            // means passcode-gated, GLOBE means public. Same glyphs and the same
            // frozen > private > public priority the web list uses.
            if density != .full {
                EmptyView()
            } else if note.frozen == true {
                badge("lock.fill", .orange, "Locked - no edits, cannot be trashed")
            } else if note.locked == true {
                badge("key.fill", Color(nsColor: .systemTeal), "Private - passcode to view")
            } else if note.isPublic == true {
                badge("globe", .green, "Public - anyone with the link")
            }

            if density == .full { SubmitterBadge(note: note) }

            // In TRASH the date that matters is the deadline, not the creation time:
            // the server purges on its own 7 day schedule.
            if density != .full {
                EmptyView()
            } else if let days = note.daysLeft {
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

/// The sidebar filter, in AppKit.
///
/// SwiftUI's TextField keeps the arrow keys for the caret, and a global key
/// monitor never saw Down at all - the letters arrived, keyCode 125 never did. An
/// NSTextField hands moveDown:/moveUp: to its delegate, which is the hook a search
/// field is supposed to have: type, then walk the results without touching the
/// mouse or leaving the field.
struct FilterField: NSViewRepresentable {
    @Binding var text: String
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = GuardedTextField()
        field.placeholderString = "Filter by title"
        field.font = .systemFont(ofSize: 12)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Only when it differs - assigning while typing resets the insertion point.
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let parent: FilterField
        init(_ parent: FilterField) { self.parent = parent }

        func controlTextDidChange(_ note: Notification) {
            guard let field = note.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)):   parent.onStep(1);  return true
            case #selector(NSResponder.moveUp(_:)):     parent.onStep(-1); return true
            default: return false
            }
        }
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

/// Who posted the open note, bottom left over the page: the device or app icon
/// by itself, no chrome. Name and time live in the tooltip and the footer.
struct SubmitterChip: View {
    let note: Note

    var body: some View {
        SubmitterBadge(note: note, size: 36)
            .padding(14)
            .help("Posted by \(note.submitterName) \u{00B7} \(note.createdStamp)")
            .accessibilityLabel("Posted by \(note.submitterName), \(note.createdStamp)")
    }
}

/// The web app's footer bar: who, when, how long ago, and the folder. Shown only
/// with the sidebar closed - open, the list row already carries all of it.
struct NoteFooter: View {
    let note: Note

    var body: some View {
        HStack(spacing: 6) {
            SubmitterBadge(note: note)
            Text("Posted by \(note.submitterName)")
            Text("\u{00B7}").foregroundStyle(.tertiary)
            Text(note.createdStamp).monospacedDigit()
            if let ago = note.createdAgo {
                Text("\u{00B7}").foregroundStyle(.tertiary)
                Text(ago)
            }
            Spacer()
            if let folder = note.folderName { Text(folder) }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Who posted the note, as the web list shows it: the posting app's icon, the
/// device's, or the owner's avatar. Served by the notes app, so it is the same
/// artwork both places. An unknown key has no icon file - that falls back to a
/// initials chip rather than a broken image.
struct SubmitterBadge: View {
    let note: Note
    var size: CGFloat = 16
    /// Which candidate is being tried. A 404 walks to the next one, and the last is
    /// the default icon, so the row always ends up with a picture.
    @State private var attempt = 0

    var body: some View {
        let candidates = note.submitterIconURLs
        AsyncImage(url: candidates[min(attempt, candidates.count - 1)]) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            case .failure:
                Color.clear.onAppear {
                    if attempt < candidates.count - 1 { attempt += 1 }
                }
            case .empty:
                Color.clear
            @unknown default:
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .help(note.createdByKey ?? note.createdByMachine ?? "Created in the notes app")
    }
}
