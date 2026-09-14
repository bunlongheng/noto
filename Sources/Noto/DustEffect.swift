import AppKit
import WebKit

/// The dissolve a trashed note leaves behind.
///
/// A snapshot of the open note is laid over the pane and erased left to right by a
/// gradient mask, with an emitter throwing dust off the erase front. The dust is
/// tinted with colours sampled from the note itself - a fixed particle colour read
/// as confetti thrown ON the page rather than the page coming apart.
///
/// What the erase uncovers is the NEXT note, blurred and transparent and sharpening
/// into place, not the window background. It is uncovered only once the trash call
/// has actually moved the selection: reveal any earlier and the erase would expose
/// a second copy of the note being destroyed.
@MainActor
enum Dust {
    private static let duration: CFTimeInterval = 0.9

    /// Play it over `web`, running `trash` as the note comes apart.
    ///
    /// `trash` starts only once the snapshot is taken - the note has to still be on
    /// screen for that - and the next note is unveiled the moment it returns. With no
    /// web view (nothing open) the work runs straight away and nothing is drawn.
    static func dissolve(over web: WKWebView?, trash: @escaping @MainActor () async -> Void) {
        guard let web, let container = web.window?.contentView, web.bounds.width > 1 else {
            Task { await trash() }; return
        }
        web.takeSnapshot(with: nil) { image, _ in
            MainActor.assumeIsolated {
                guard let shot = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    Task { await trash() }; return
                }
                let backdrop = play(shot, over: web, in: container,
                                    frame: container.convert(web.bounds, from: web))
                let start = Date()
                Task {
                    await trash()
                    // The next note is selected now. Give the web view a beat to paint
                    // it, and never uncover it before the erase has bitten into the
                    // page - the trash call can return in 80ms, which would have the
                    // new note sharp while the old one was still whole.
                    let waited = Date().timeIntervalSince(start)
                    try? await Task.sleep(for: .seconds(max(0.1, 0.3 - waited)))
                    reveal(web, over: backdrop)
                }
            }
        }
    }

    /// Returns the out-of-focus backdrop, which the reveal fades out.
    @discardableResult
    private static func play(_ snapshot: CGImage, over web: WKWebView,
                             in container: NSView, frame: CGRect) -> CALayer? {
        // Hidden only until the next note is in place; `reveal` brings it back.
        web.alphaValue = 0
        let overlay = NSView(frame: frame)
        overlay.wantsLayer = true
        // Core Image filters on a layer are ignored unless the host view opts in.
        overlay.layerUsesCoreImageFilters = true
        container.addSubview(overlay)
        guard let root = overlay.layer else { return nil }
        // Dust that crosses into the sidebar and the tab strip reads as a glitch
        // rather than as the note coming apart. It stays in the pane it came from.
        root.masksToBounds = true

        // What the erase uncovers until the next note is ready: the same note thrown
        // out of focus. The window's own background behind the pane is near-black, and
        // flashing it mid-delete reads as a bug rather than as a dissolve.
        let backdrop = CALayer()
        backdrop.frame = overlay.bounds
        backdrop.contents = snapshot
        backdrop.contentsGravity = .resize
        // Scaled up a touch: a Gaussian blur thins out at the edges, and the overscan
        // keeps the soft border off screen.
        backdrop.transform = CATransform3DMakeScale(1.07, 1.07, 1)
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(26, forKey: kCIInputRadiusKey)
            backdrop.filters = [blur]
        }
        root.addSublayer(backdrop)

        let picture = CALayer()
        picture.frame = overlay.bounds
        picture.contents = snapshot
        picture.contentsGravity = .resize
        root.addSublayer(picture)

        // Colours are a hair past 1 so the last sliver is fully gone at the end.
        let mask = CAGradientLayer()
        mask.frame = overlay.bounds
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        let gone = NSColor.black.withAlphaComponent(0).cgColor
        mask.colors = [gone, gone, NSColor.black.cgColor, NSColor.black.cgColor]
        mask.locations = [-0.34, -0.18, 0, 0.06]
        picture.mask = mask

        // A rectangle, not a line: CAEmitterLayer's line lies along X, so a "line"
        // emitted dust from one point at mid-height instead of down the whole edge.
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .rectangle
        emitter.emitterSize = CGSize(width: 70, height: overlay.bounds.height)
        emitter.emitterPosition = CGPoint(x: 40, y: overlay.bounds.midY)
        emitter.emitterCells = bandColors(snapshot).map { cell($0) }
        root.addSublayer(emitter)

        animate(mask, key: "locations",
                from: mask.locations!, to: [1.0, 1.16, 1.34, 1.4] as [NSNumber], ease: .easeIn)
        // "emitterPosition.x" animates nothing - the sub-keypath is not animatable
        // here, and the dust piled up at the left edge instead of following the
        // erase. The whole point, boxed, does move.
        animate(emitter, key: "emitterPosition",
                from: NSValue(point: emitter.emitterPosition),
                to: NSValue(point: CGPoint(x: overlay.bounds.width, y: overlay.bounds.midY)),
                ease: .easeIn)

        Task {
            try? await Task.sleep(for: .seconds(duration))
            emitter.birthRate = 0            // stop making dust; what is airborne keeps flying
            try? await Task.sleep(for: .seconds(1.2))
            overlay.removeFromSuperview()
        }
        return backdrop
    }

    /// Bring the next note up out of focus and let it settle - opacity climbing from
    /// nothing while the blur falls away, so it is arriving through the dust rather
    /// than cutting in behind it.
    private static func reveal(_ web: WKWebView, over backdrop: CALayer?) {
        guard web.alphaValue == 0 else { return }     // never reveal twice
        // The blurred stand-in hands over to the real note, so there is never a frame
        // of bare background between them.
        if let backdrop {
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = 1
            out.toValue = 0
            out.duration = 0.5
            out.fillMode = .forwards
            out.isRemovedOnCompletion = false
            backdrop.add(out, forKey: "handover")
        }
        web.wantsLayer = true
        web.layerUsesCoreImageFilters = true
        guard let layer = web.layer else { web.alphaValue = 1; return }

        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.setValue(22, forKey: kCIInputRadiusKey)
        blur?.name = "settle"
        layer.filters = blur.map { [$0] }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let sharpen = CABasicAnimation(keyPath: "filters.settle.inputRadius")
        sharpen.fromValue = 22
        sharpen.toValue = 0
        let settle = CABasicAnimation(keyPath: "transform.scale")
        settle.fromValue = 1.04
        settle.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [fade, sharpen, settle]
        group.duration = 0.65
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "arrive")

        web.alphaValue = 1
        Task {
            try? await Task.sleep(for: .seconds(0.7))
            layer.filters = nil              // a live blur filter would cost every frame after
        }
    }

    private static func animate(_ layer: CALayer, key: String, from: Any, to: Any,
                                ease: CAMediaTimingFunctionName) {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: ease)
        a.fillMode = .forwards
        a.isRemovedOnCompletion = false
        layer.add(a, forKey: key)
    }

    private static func cell(_ color: CGColor) -> CAEmitterCell {
        let c = CAEmitterCell()
        c.contents = speck
        c.color = color
        c.birthRate = 1400
        c.lifetime = 1.1
        c.lifetimeRange = 0.4
        c.velocity = 60
        c.velocityRange = 48
        c.emissionLongitude = .pi / 2.6     // up, leaning the way the erase travels
        c.emissionRange = .pi / 2.6
        c.yAcceleration = 45
        c.xAcceleration = 45
        c.scale = 0.95
        c.scaleRange = 0.5
        c.scaleSpeed = -0.35
        c.alphaSpeed = -0.85
        c.spin = 1.2
        c.spinRange = 2.6
        return c
    }

    /// One soft speck, drawn once and tinted per cell.
    private static let speck: CGImage = {
        let side = 18
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let stops = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: stops, locations: [0, 1])!
        let mid = CGPoint(x: side / 2, y: side / 2)
        ctx.drawRadialGradient(gradient, startCenter: mid, startRadius: 0,
                               endCenter: mid, endRadius: CGFloat(side) / 2, options: [])
        return ctx.makeImage()!
    }()

    /// Three colours down the note, so the dust matches what it came from.
    private static func bandColors(_ image: CGImage, count: Int = 3) -> [CGColor] {
        var pixels = [UInt8](repeating: 0, count: count * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: 1, height: count, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return [NSColor.white.cgColor]
        }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: count))
        return (0..<count).map { i in
            let o = i * 4
            return CGColor(red: CGFloat(pixels[o]) / 255, green: CGFloat(pixels[o + 1]) / 255,
                           blue: CGFloat(pixels[o + 2]) / 255, alpha: 0.95)
        }
    }
}
