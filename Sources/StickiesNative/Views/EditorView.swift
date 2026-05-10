import SwiftUI
import AppKit

struct EditorView: View {
    let note: Note
    @EnvironmentObject var appState: AppState
    @State private var attributedText = NSAttributedString()
    @State private var isLoadingContent = true
    @State private var saveTimer: Timer?
    @State private var hasUnsavedChanges = false

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack(spacing: 10) {
                if let color = note.parsedColor {
                    Circle()
                        .fill(Color(red: color.r, green: color.g, blue: color.b))
                        .frame(width: 12, height: 12)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.system(size: 16, weight: .semibold))
                    HStack(spacing: 8) {
                        if let folder = note.folderName {
                            Text(folder)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Text(note.displayDate)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if hasUnsavedChanges {
                    Text("Unsaved")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }

                Button {
                    saveNow()
                } label: {
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .help("Save to server (Cmd+S)")
                .keyboardShortcut("s", modifiers: .command)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Formatting toolbar
            ToolbarView(textView: nil)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))

            Divider()

            // Editor
            if isLoadingContent {
                VStack {
                    Spacer()
                    ProgressView()
                    Text("Loading content...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                    Spacer()
                }
            } else {
                RichTextEditor(
                    attributedText: $attributedText,
                    onTextChange: {
                        hasUnsavedChanges = true
                        scheduleSave()
                    }
                )
            }
        }
        .task {
            await loadContent()
        }
        .onDisappear {
            saveTimer?.invalidate()
            if hasUnsavedChanges {
                saveNow()
            }
        }
    }

    private func loadContent() async {
        isLoadingContent = true
        if let content = await appState.loadNoteContent(id: note.id) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ]
            attributedText = NSAttributedString(string: content, attributes: attrs)
        } else {
            attributedText = NSAttributedString(string: note.content ?? "")
        }
        isLoadingContent = false
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [self] _ in
            Task { @MainActor in
                saveNow()
            }
        }
    }

    private func saveNow() {
        guard hasUnsavedChanges else { return }
        let content = attributedText.string
        hasUnsavedChanges = false
        Task {
            await appState.updateNote(id: note.id, content: content)
        }
    }
}

// MARK: - NSTextView wrapper for rich text editing

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var onTextChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesFindBar = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsImageEditing = true
        textView.importsGraphics = true

        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 16, height: 16)

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        textView.textStorage?.setAttributedString(attributedText)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // Only update if the text actually differs (avoid cursor jump)
        if textView.attributedString() != attributedText {
            let selectedRanges = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributedText)
            textView.selectedRanges = selectedRanges
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.attributedText = textView.attributedString()
            parent.onTextChange()
        }

        // Support pasting images
        func textView(_ textView: NSTextView, willPaste pasteboard: NSPasteboard) -> Bool {
            // Let NSTextView handle image pasting natively
            return false
        }
    }
}
