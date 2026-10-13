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
        .background(.black, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
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
