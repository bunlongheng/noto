import AVFoundation

/// The sound a note makes on its way out.
///
/// Synthesised, not shipped: one noise burst through a filter band that sweeps
/// upward, with the level held back until the erase rips across. That is ~30 lines
/// here against an audio file in the bundle, a build step to copy it, and a licence
/// to track. Built once on first use and replayed from the same buffer.
@MainActor
enum Whoosh {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var buffer: AVAudioPCMBuffer?
    private static var wired = false

    static func play() {
        guard let buffer = buffer ?? build() else { return }
        if !wired {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            wired = true
        }
        // A sound is never worth failing a delete over - if the device is busy or
        // unavailable, the dissolve just plays silently.
        if !engine.isRunning, (try? engine.start()) == nil { return }
        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    private static func build() -> AVAudioPCMBuffer? {
        let rate = 44_100.0, seconds = 1.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(rate * seconds))
        else { return nil }
        buf.frameLength = buf.frameCapacity
        let samples = buf.floatChannelData![0]

        var low: Float = 0, lower: Float = 0
        var seed: UInt32 = 0x9E37_79B9
        let peak: Float = 0.62          // where the erase is at full speed
        for i in 0..<Int(buf.frameLength) {
            let t = Float(i) / Float(buf.frameLength)
            // xorshift: a tight audio loop has no business calling into Foundation.
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max)
            // Two one-pole lowpasses whose cutoffs climb; their difference is a band
            // that rises in pitch, which is what reads as a whoosh.
            let fast = 0.02 + 0.5 * t * t
            low += fast * (noise - low)
            lower += (fast * 0.3) * (noise - lower)
            let envelope = t < peak ? powf(t / peak, 2.0) : expf(-7 * (t - peak))
            samples[i] = (low - lower) * envelope * 0.6
        }
        buffer = buf
        return buf
    }
}

/// The tick a list row makes under the pointer - the web list's hover sound:
/// 30ms, 12ms attack, throttled to one per 80ms. A sine, not the web's square,
/// and quieter: the square's harmonics read as noise through Mac speakers.
@MainActor
enum HoverTick {
    private static let engine = AVAudioEngine()
    private static let player = AVAudioPlayerNode()
    private static var buffer: AVAudioPCMBuffer?
    private static var wired = false
    private static var last = Date.distantPast

    static func play() {
        guard Date().timeIntervalSince(last) >= 0.08 else { return }
        last = Date()
        guard let buffer = buffer ?? build() else { return }
        if !wired {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            wired = true
        }
        if !engine.isRunning, (try? engine.start()) == nil { return }
        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    private static func build() -> AVAudioPCMBuffer? {
        let rate = 44_100.0, seconds = 0.05
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: format,
                                         frameCapacity: AVAudioFrameCount(rate * seconds))
        else { return nil }
        buf.frameLength = buf.frameCapacity
        let samples = buf.floatChannelData![0]
        let volume: Float = 0.006
        for i in 0..<Int(buf.frameLength) {
            let t = Float(i) / Float(rate)
            let wave = sinf(2 * .pi * 2400 * t)
            // Linear ramp up over 12ms, then an exponential fall to 0.001 by 30ms.
            let envelope = t < 0.012 ? t / 0.012 : (t < 0.03 ? powf(0.001 / volume, (t - 0.012) / 0.018) : 0)
            samples[i] = wave * volume * envelope
        }
        buffer = buf
        return buf
    }
}
