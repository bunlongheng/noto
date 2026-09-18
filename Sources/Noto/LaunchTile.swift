import SwiftUI

/// What the web app shows while a note's body is on the way, rebuilt here: a tile
/// in the note's own colour carrying its initial, breathing.
///
/// Same numbers as app/(app)/page.tsx's `noteLaunchBreath` - a 1s cycle between
/// scale 0.9 at -3 degrees and scale 1.05 at +2, opacity 0.85 to 1 - so a note
/// opening in Noto and a note opening in the browser look like the same app.
struct LaunchTile: View {
    let note: Note
    @State private var breathing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 23, style: .continuous)
            .fill(color)
            .frame(width: 96, height: 96)
            .overlay(
                Text(initial)
                    .font(.system(size: 40, weight: .black))
                    .foregroundStyle(ink)
            )
            .shadow(color: color.opacity(0.73), radius: 24)
            .scaleEffect(breathing ? 1.05 : 0.9)
            .rotationEffect(.degrees(breathing ? 2 : -3))
            .opacity(breathing ? 1 : 0.85)
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: breathing)
            .onAppear { breathing = true }
            .accessibilityLabel("Loading \(note.title)")
    }

    /// First letter or digit of the title, uppercased - the web's meaningfulInitial.
    private var initial: String {
        let first = note.title.first { $0.isLetter || $0.isNumber }
        return String(first ?? "N").uppercased()
    }

    private var color: Color {
        guard let c = note.parsedColor else { return Color(nsColor: .systemGray) }
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// Dark ink on a light tile, white on a dark one - the same call the web makes
    /// so the initial never disappears into its own background.
    private var ink: Color {
        guard let c = note.parsedColor else { return .white }
        let luminance = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        return luminance > 0.65 ? Color(red: 0.11, green: 0.11, blue: 0.12) : .white
    }
}
