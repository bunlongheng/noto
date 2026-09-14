import AppKit
import SwiftUI

@main
struct StickiesNativeApp: App {
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
            CommandGroup(replacing: .newItem) { }   // read-mostly app, no New
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
                Button("Move to Trash") { Task { await state.trashSelected() } }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(state.selectedNote == nil)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var host: WebHost
    @State private var find = ""
    @State private var keyMonitor: Any?

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
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(state.selectedNote == nil)
                .onReceive(NotificationCenter.default.publisher(for: .focusFind)) { _ in
                    if state.selectedNote != nil { host.focusFind() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await state.trashSelected() } } label: { Image(systemName: "trash") }
                    .disabled(state.selectedNote == nil)
                    .help("Move to TRASH (Cmd+Delete)")
                    .accessibilityLabel("Move note to trash")
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
                Text("All Notes").font(.system(size: 15, weight: .semibold))
                Text(state.query.isEmpty ? "\(state.notes.count)" : "\(state.visible.count) of \(state.notes.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Spacer()
                if state.isLoading { ProgressView().scaleEffect(0.5) }
                Button { state.load() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh (Cmd+R)").accessibilityLabel("Refresh notes")
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Search all notes", text: $state.query)
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
                    NoteRow(note: note).tag(note.id)
                }
                .listStyle(.inset)
            }
        }
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

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: NoteIcon.symbol(for: note.icon))
                .font(.system(size: 13))
                .frame(width: 18)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let folder = note.folderName, !folder.isEmpty {
                    Text(folder).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(note.displayDate).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    /// Keep the folder colour the dot used to carry - now it tints the icon.
    private var tint: Color {
        guard let c = note.parsedColor else { return .secondary }
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}
