import SwiftUI
import AppKit

struct EditorView: View {
    let note: Note
    @EnvironmentObject var appState: AppState
    @State private var attributedText = NSAttributedString()
    @State private var isLoadingContent = true
    @State private var saveTimer: Timer?
    @State private var hasUnsavedChanges = false
    @State private var isSaving = false

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

                if isSaving {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.5)
                        Text("Saving...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.blue)
                    }
                } else if hasUnsavedChanges {
                    Text("Unsaved")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }

                Button {
                    Task { await saveNow() }
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
                    apiClient: appState.apiClient,
                    folderName: note.folderName ?? "native",
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
                Task { await saveNow() }
            }
        }
    }

    private func loadContent() async {
        isLoadingContent = true
        if let content = await appState.loadNoteContent(id: note.id) {
            let noteType = note.type ?? "text"
            if noteType == "html" || content.contains("<") && content.contains(">") {
                // Parse HTML into attributed string
                if let htmlData = content.data(using: .utf8),
                   let attrStr = try? NSAttributedString(
                       data: htmlData,
                       options: [
                           .documentType: NSAttributedString.DocumentType.html,
                           .characterEncoding: String.Encoding.utf8.rawValue
                       ],
                       documentAttributes: nil
                   ) {
                    attributedText = attrStr
                } else {
                    attributedText = makeDefaultString(content)
                }
            } else {
                attributedText = makeDefaultString(content)
            }
        } else {
            attributedText = makeDefaultString(note.content ?? "")
        }
        isLoadingContent = false
    }

    private func makeDefaultString(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ])
    }

    private func scheduleSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [self] _ in
            Task { @MainActor in
                await saveNow()
            }
        }
    }

    private func saveNow() async {
        guard hasUnsavedChanges else { return }
        isSaving = true
        hasUnsavedChanges = false

        // Extract images, upload to GDrive, replace with <img> tags
        let processed = await processImagesForUpload(attributedText, apiClient: appState.apiClient, folder: note.folderName ?? "native")

        // Convert to HTML
        let html = attributedStringToHTML(processed)

        await appState.updateNote(id: note.id, content: html)
        isSaving = false
    }
}

// MARK: - Image processing: extract embedded images, upload, replace with URLs

func processImagesForUpload(_ attrString: NSAttributedString, apiClient: APIClient, folder: String) async -> NSAttributedString {
    let mutable = NSMutableAttributedString(attributedString: attrString)
    var imageRanges: [(NSRange, NSTextAttachment)] = []

    // Find all image attachments
    mutable.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
        if let attachment = value as? NSTextAttachment {
            imageRanges.append((range, attachment))
        }
    }

    // Process in reverse order so ranges stay valid
    for (range, attachment) in imageRanges.reversed() {
        var imageData: Data?

        if let data = attachment.contents {
            imageData = data
        } else if let image = attachment.image {
            imageData = image.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
            }
        } else if let cell = attachment.attachmentCell as? NSTextAttachmentCell,
                  let image = cell.image {
            imageData = image.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
            }
        }

        guard let data = imageData else { continue }

        let filename = "native-\(UUID().uuidString.prefix(8)).png"
        do {
            let url = try await apiClient.uploadImage(imageData: data, filename: filename, folder: folder)
            let imgTag = "<img src=\"\(url)\" alt=\"\(filename)\" style=\"max-width:100%\">"
            let replacement = NSAttributedString(string: imgTag, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ])
            mutable.replaceCharacters(in: range, with: replacement)
        } catch {
            // Keep the attachment if upload fails
        }
    }

    return mutable
}

// MARK: - Convert NSAttributedString to HTML

func attributedStringToHTML(_ attrString: NSAttributedString) -> String {
    // If the string already contains img tags (from uploaded images), use a hybrid approach
    let plainText = attrString.string

    // Check if there are any remaining attachments (shouldn't be after processing)
    var hasAttachments = false
    attrString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attrString.length)) { value, _, stop in
        if value != nil { hasAttachments = true; stop.pointee = true }
    }

    // Try native HTML export for rich text
    if let htmlData = try? attrString.data(
        from: NSRange(location: 0, length: attrString.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
    ), let html = String(data: htmlData, encoding: .utf8) {
        // Clean up the HTML - extract just the body content
        if let bodyStart = html.range(of: "<body>"),
           let bodyEnd = html.range(of: "</body>") {
            let bodyContent = String(html[bodyStart.upperBound..<bodyEnd.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return bodyContent
        }
        return html
    }

    // Fallback: return plain text
    return plainText
}

// MARK: - NSTextView wrapper for rich text editing

struct RichTextEditor: NSViewRepresentable {
    @Binding var attributedText: NSAttributedString
    var apiClient: APIClient
    var folderName: String
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

        // Register for file drops
        textView.registerForDraggedTypes([.fileURL, .png, .tiff, .pdf])

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

        @objc func zoomIn() {
            changeFontSize(by: 2)
        }

        @objc func zoomOut() {
            changeFontSize(by: -2)
        }

        private func changeFontSize(by delta: CGFloat) {
            guard let textView, let storage = textView.textStorage else { return }
            let range = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                if let font = value as? NSFont {
                    let newSize = max(8, font.pointSize + delta)
                    let newFont = NSFontManager.shared.convert(font, toSize: newSize)
                    storage.addAttribute(.font, value: newFont, range: attrRange)
                }
            }
            storage.endEditing()
            parent.attributedText = textView.attributedString()
            parent.onTextChange()
        }

        func textView(_ textView: NSTextView, willPaste pasteboard: NSPasteboard) -> Bool {
            return false
        }
    }
}
