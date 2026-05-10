import SwiftUI
import AppKit

struct ToolbarView: View {
    let textView: NSTextView?

    var body: some View {
        HStack(spacing: 2) {
            FormatButton(icon: "bold", tooltip: "Bold (Cmd+B)") {
                applyFontTrait(.boldFontMask)
            }
            FormatButton(icon: "italic", tooltip: "Italic (Cmd+I)") {
                applyFontTrait(.italicFontMask)
            }
            FormatButton(icon: "underline", tooltip: "Underline (Cmd+U)") {
                applyUnderline()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            FormatButton(icon: "text.alignleft", tooltip: "Align Left") {
                applyAlignment(.left)
            }
            FormatButton(icon: "text.aligncenter", tooltip: "Align Center") {
                applyAlignment(.center)
            }
            FormatButton(icon: "text.alignright", tooltip: "Align Right") {
                applyAlignment(.right)
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            FormatButton(icon: "list.bullet", tooltip: "Bullet List") {
                insertBulletList()
            }
            FormatButton(icon: "tablecells", tooltip: "Insert Table") {
                insertTable()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Menu {
                ForEach([12, 14, 16, 18, 20, 24, 28, 32], id: \.self) { size in
                    Button("\(size) pt") {
                        applyFontSize(CGFloat(size))
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "textformat.size")
                        .font(.system(size: 12))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 50)

            Spacer()
        }
    }

    private func getActiveTextView() -> NSTextView? {
        if let tv = textView { return tv }
        // Get the first responder text view from the key window
        guard let window = NSApp.keyWindow else { return nil }
        return window.firstResponder as? NSTextView
    }

    private func applyFontTrait(_ trait: NSFontTraitMask) {
        guard let tv = getActiveTextView() else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }

        tv.textStorage?.beginEditing()
        tv.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            let manager = NSFontManager.shared
            let newFont: NSFont
            if manager.traits(of: font).contains(trait) {
                newFont = manager.convert(font, toNotHaveTrait: trait)
            } else {
                newFont = manager.convert(font, toHaveTrait: trait)
            }
            tv.textStorage?.addAttribute(.font, value: newFont, range: attrRange)
        }
        tv.textStorage?.endEditing()
        tv.didChangeText()
    }

    private func applyUnderline() {
        guard let tv = getActiveTextView() else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }

        tv.textStorage?.beginEditing()
        var isUnderlined = false
        tv.textStorage?.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
            if let style = value as? Int, style != 0 {
                isUnderlined = true
            }
        }
        let style: Int = isUnderlined ? 0 : NSUnderlineStyle.single.rawValue
        tv.textStorage?.addAttribute(.underlineStyle, value: style, range: range)
        tv.textStorage?.endEditing()
        tv.didChangeText()
    }

    private func applyAlignment(_ alignment: NSTextAlignment) {
        guard let tv = getActiveTextView() else { return }
        let range = tv.selectedRange()
        let paragraphRange = (tv.string as NSString).paragraphRange(for: range)

        tv.textStorage?.beginEditing()
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        tv.textStorage?.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
        tv.textStorage?.endEditing()
        tv.didChangeText()
    }

    private func applyFontSize(_ size: CGFloat) {
        guard let tv = getActiveTextView() else { return }
        let range = tv.selectedRange()
        guard range.length > 0 else { return }

        tv.textStorage?.beginEditing()
        tv.textStorage?.enumerateAttribute(.font, in: range, options: []) { value, attrRange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: size)
            let newFont = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
            tv.textStorage?.addAttribute(.font, value: newFont, range: attrRange)
        }
        tv.textStorage?.endEditing()
        tv.didChangeText()
    }

    private func insertBulletList() {
        guard let tv = getActiveTextView() else { return }
        let insertion = "\n- "
        tv.insertText(insertion, replacementRange: tv.selectedRange())
    }

    private func insertTable() {
        guard let tv = getActiveTextView() else { return }
        let table = "\n| Column 1 | Column 2 | Column 3 |\n|----------|----------|----------|\n| Cell 1   | Cell 2   | Cell 3   |\n| Cell 4   | Cell 5   | Cell 6   |\n"
        tv.insertText(table, replacementRange: tv.selectedRange())
    }
}

struct FormatButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(4)
        .help(tooltip)
    }
}
