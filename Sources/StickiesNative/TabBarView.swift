import AppKit
import SwiftUI

/// The tab strip above the note, mirroring the web app's tabs view.
///
/// Full screen hides the sidebar, which left no way to reach another note without
/// leaving the one being read. Inactive tabs are icon-only in their folder colour
/// so many fit; the active tab grows, keeps its title and carries the close button.
/// The < > stepper on the right - and the plain arrow keys - flick through the
/// notes one at a time, the way the web app does.
struct TabBarView: View {
    @EnvironmentObject var state: AppState

    private let h: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .bottom, spacing: 2) {
                        ForEach(state.tabs) { note in
                            tab(note).id(note.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: h + 6, alignment: .bottom)
                }
                // Selection also moves from the sidebar, the stepper and the arrow
                // keys, so the active tab has to be scrolled into view rather than
                // assumed visible.
                .onChange(of: state.selected) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            stepper
        }
        .frame(height: h + 6)
        .background(Color.secondary.opacity(0.16))
    }

    /// < ALL (n) > - the same trailing control the web strip carries.
    private var stepper: some View {
        HStack(spacing: 2) {
            arrow("chevron.left", -1, "Previous note (←)")
            Text("ALL (\(state.tabs.count))")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .fixedSize()
            arrow("chevron.right", 1, "Next note (→)")
        }
        .padding(.horizontal, 6)
        .frame(height: h + 6)
    }

    private func arrow(_ symbol: String, _ direction: Int, _ help: String) -> some View {
        Button { state.stepTab(direction) } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(state.tabs.count < 2)
        .help(help)
        .accessibilityLabel(help)
    }

    @ViewBuilder
    private func tab(_ note: Note) -> some View {
        let active = note.id == state.selected
        let tint = color(note)
        HStack(spacing: 5) {
            Image(systemName: NoteIcon.symbol(for: note.icon))
                .font(.system(size: 11))
            if active {
                Text(note.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button { state.closeTab(note.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab")
            }
        }
        .foregroundStyle(foreground(tint))
        .padding(.horizontal, active ? 9 : 7)
        .frame(height: active ? h + 6 : h)
        .frame(maxWidth: active ? 190 : nil)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                .fill(tint.opacity(active ? 1 : 0.55))
        )
        .opacity(active ? 1 : 0.85)
        .contentShape(Rectangle())
        .onTapGesture { state.selected = note.id }
        .help(note.title)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private func color(_ note: Note) -> Color {
        guard let c = note.parsedColor else { return .gray }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// Folder colours run from pale yellow to near-black, so the label has to pick
    /// its ink from the tab's own luminance instead of always being white.
    private func foreground(_ tint: Color) -> Color {
        guard let c = NSColor(tint).usingColorSpace(.sRGB) else { return .white }
        let luma = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return luma > 0.6 ? Color(red: 0.11, green: 0.11, blue: 0.12) : .white
    }
}
