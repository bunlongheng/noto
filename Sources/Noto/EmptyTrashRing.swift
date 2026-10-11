import AppKit
import SwiftUI

/// The big ring shown while TRASH empties: it fills, the bin shakes in the middle
/// with the notes left counting down, and a check lands when the server says done.
struct EmptyTrashRing: View {
    let progress: Double
    let count: Int
    @State private var spin = false

    private var done: Bool { progress >= 1 }
    private var left: Int { Int((Double(count) * (1 - progress)).rounded(.up)) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 18)
                // A dashed orbit turning behind the fill, so the ring never looks frozen.
                Circle()
                    .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [3, 9]))
                    .padding(-22)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: spin)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: [.orange, .red, .pink, .orange], center: .center),
                            style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .red.opacity(0.6), radius: 12)
                    .animation(.easeInOut(duration: 0.25), value: progress)
                VStack(spacing: 10) {
                    Image(systemName: done ? "checkmark.circle.fill" : "trash.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(done ? AnyShapeStyle(.green) : AnyShapeStyle(.white))
                        .symbolEffect(.bounce, value: left)
                        .contentTransition(.symbolEffect(.replace))
                    Text(done ? "Gone for good" : "\(left) left")
                        .font(.title3.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .contentTransition(.numericText())
                        .animation(.default, value: left)
                }
            }
            .frame(width: 260, height: 260)
            .padding(48)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 36))
            .scaleEffect(done ? 1.04 : 1)
            .animation(.spring(duration: 0.35, bounce: 0.5), value: done)
        }
        .onAppear { spin = true }
    }
}

/// The Finder's own empty-trash crunch, so it sounds like emptying the Mac's bin.
enum TrashSound {
    static let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/empty trash.aif"
    static func play() { NSSound(contentsOfFile: path, byReference: true)?.play() }
}
