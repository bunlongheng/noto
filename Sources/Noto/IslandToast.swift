import SwiftUI

/// A tiny robot that lives in the toast: round head, 2 eyes that blink, a green
/// antenna light. Drawn in code so it needs no asset and scales with the text.
struct Mascot: View {
    @State private var blink = false

    var body: some View {
        VStack(spacing: 0) {
            Circle().fill(.green).frame(width: 4, height: 4)
                .shadow(color: .green, radius: 2)
            Rectangle().fill(.white.opacity(0.6)).frame(width: 1.5, height: 3)
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 18, height: 14)
                HStack(spacing: 4) {
                    Capsule().fill(.black).frame(width: 4, height: blink ? 1 : 5)
                    Capsule().fill(.black).frame(width: 4, height: blink ? 1 : 5)
                }
                .offset(y: -1.5)
                Capsule().fill(.black.opacity(0.55)).frame(width: 7, height: 1.5).offset(y: 4)
            }
        }
        .task {
            // Blinks every couple of seconds for as long as the toast is up.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeInOut(duration: 0.08)) { blink = true }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.easeInOut(duration: 0.08)) { blink = false }
            }
        }
    }
}

/// The toast as a Dynamic Island: a black pill dropping from the top centre, the
/// mascot on the left, white text, and Undo when a trash move can still be undone.
struct IslandToast: View {
    @EnvironmentObject var state: AppState
    let toast: Toast
    private var tone: Color { toast.kind == .success ? .green : .orange }

    var body: some View {
        HStack(spacing: 10) {
            Mascot()
            Image(systemName: toast.symbol)
                .foregroundStyle(toast.kind == .success ? .green : .orange)
            Text(toast.text).lineLimit(2)
            if toast.kind == .success, state.canUndoTrash {
                Button("Undo") { Task { await state.undoTrash() } }
                    .buttonStyle(.link)
                    .keyboardShortcut("z", modifiers: .command)
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.white)
        .padding(.leading, 12).padding(.trailing, 18).padding(.vertical, 9)
        .background(GeometryReader { g in Fireflies(around: g.size) })
        .background(Capsule().fill(.black).overlay(Capsule().fill(tone.opacity(0.16))))
        .overlay(Capsule().strokeBorder(tone.opacity(0.85), lineWidth: 1.5))
        .shadow(color: tone.opacity(0.45), radius: 14, y: 2)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        .padding(.top, 10)
        .transition(.scale(scale: 0.4, anchor: .top).combined(with: .opacity))
    }
}

/// The whole window goes green for a beat with "Copied" across it, so a copy
/// for an agent is impossible to miss. Never blocks a click.
struct CopiedFlash: View {
    var body: some View {
        ZStack {
            Color.green.opacity(0.55).ignoresSafeArea()
            Text("Copied")
                .font(.system(size: 110, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
        .allowsHitTesting(false)
    }
}

/// Colourful motes that burst from the pill's edge, drift out and wink out, then
/// burst again while the toast is up - the Stickies firefly, around a toast.
struct Fireflies: View {
    let around: CGSize
    @Environment(\.accessibilityReduceMotion) private var stillness
    @State private var flown = false
    @State private var motes: [Mote] = []

    private struct Mote: Identifiable {
        let id = UUID()
        let color: Color
        let from: CGSize, to: CGSize
        let delay: Double, duration: Double
        let size: CGFloat
    }

    private static let palette: [Color] = [.green, .mint, .yellow, .cyan, .pink, .orange, .purple]

    private func spawn() -> [Mote] {
        (0..<16).map { i in
            let a = Double(i) / 16 * 2 * .pi + .random(in: -0.25...0.25)
            let x = cos(a) * Double(around.width) / 2, y = sin(a) * Double(around.height) / 2
            let push = Double.random(in: 28...60)
            return Mote(color: Fireflies.palette.randomElement()!,
                        from: CGSize(width: x, height: y),
                        to: CGSize(width: x + cos(a) * push, height: y + sin(a) * push - 12),
                        delay: .random(in: 0...0.5), duration: .random(in: 1.4...2.2),
                        size: .random(in: 5...9))
        }
    }

    var body: some View {
        ZStack {
            ForEach(motes) { m in
                Circle().fill(m.color)
                    .frame(width: m.size, height: m.size)
                    .shadow(color: m.color, radius: 5)
                    .offset(flown ? m.to : m.from)
                    .scaleEffect(flown ? 0.4 : 1)
                    .animation(.easeOut(duration: m.duration).delay(m.delay), value: flown)
                    .opacity(flown ? 0 : 1)
                    .animation(.easeIn(duration: m.duration).delay(m.delay), value: flown)
            }
        }
        .frame(width: around.width, height: around.height)
        .allowsHitTesting(false)
        .task {
            guard !stillness else { return }
            while !Task.isCancelled {
                var still = Transaction(); still.disablesAnimations = true
                withTransaction(still) { motes = spawn(); flown = false }
                try? await Task.sleep(for: .milliseconds(30))
                flown = true
                try? await Task.sleep(for: .seconds(2.4))
            }
        }
    }
}
