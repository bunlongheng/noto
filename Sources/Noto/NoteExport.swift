import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

/// Save the whole note as one image - the entire document, not the part that
/// happens to be on screen.
///
/// The capture goes through the web view's own PDF export rather than
/// takeSnapshot: a snapshot can only return what is rendered, so anything below
/// the scroll line comes back blank or has to be stitched from a fake scroll.
/// The PDF is the page WebKit already knows how to lay out end to end, and it is
/// taken at the CURRENT width and page zoom, so the file matches what is on screen.
enum NoteExport {
    enum Format: String {
        case png, webp

        var ext: String { rawValue }
    }

    enum Failure: LocalizedError {
        case noPage
        case bitmap
        case encode(String)

        var errorDescription: String? {
            switch self {
            case .noPage:            return "the note produced no printable page"
            case .bitmap:            return "the image was too large to draw"
            case .encode(let what):  return what
            }
        }
    }

    /// WebP needs an encoder ImageIO does not ship: it decodes WebP but cannot
    /// write it. cwebp (Homebrew's libwebp) is used when it is installed, and the
    /// menu simply does not offer WebP when it is not.
    static let webpEncoder: String? = ["/opt/homebrew/bin/cwebp", "/usr/local/bin/cwebp"]
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    // MARK: - Capture

    /// Render the full document to a bitmap.
    ///
    /// Scale is 3x so the bitmap stays sharp past retina - a browser canvas that
    /// only takes the PNG can zoom in on it. Backed off only when a very long note
    /// would otherwise ask for a bitmap measured in gigabytes.
    @MainActor
    static func fullPageImage(of view: WKWebView, scale: CGFloat = 3) async throws -> CGImage {
        try await render(of: view, scale: scale).image
    }

    /// Same capture, and also the scale it actually drew at - the copy path needs
    /// it to state the note's on-screen size next to a retina bitmap.
    @MainActor
    static func render(of view: WKWebView, scale: CGFloat) async throws -> (image: CGImage, scale: CGFloat) {
        try render(pdf: try await view.pdf(configuration: WKPDFConfiguration()), scale: scale)
    }

    /// The PDF is the vector original; everything below is a raster of it.
    static func render(pdf data: Data, scale: CGFloat) throws -> (image: CGImage, scale: CGFloat) {
        guard let provider = CGDataProvider(data: data as CFData),
              let doc = CGPDFDocument(provider), doc.numberOfPages > 0 else { throw Failure.noPage }

        // Usually one page the height of the whole document. WebKit paginates it
        // in some cases, and a note split across pages must still come back as one
        // image, so the pages are stacked in order.
        let pages = (1...doc.numberOfPages).compactMap { doc.page(at: $0) }
        let boxes = pages.map { $0.getBoxRect(.mediaBox) }
        let width = boxes.map(\.width).max() ?? 0
        let height = boxes.map(\.height).reduce(0, +)
        guard width > 0, height > 0 else { throw Failure.noPage }

        // ~60 MP is about 240 MB of pixels - past that the file stops being useful
        // and starts being a memory spike.
        let maxPixels: CGFloat = 60_000_000
        var s = scale
        if width * height * s * s > maxPixels { s = max(1, sqrt(maxPixels / (width * height))) }

        let pixelWidth = Int((width * s).rounded())
        let pixelHeight = Int((height * s).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil,
                                  width: pixelWidth,
                                  height: pixelHeight,
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure.bitmap }

        // A note's HTML assumes a page under it. Without this fill, every gap in
        // the note's own background comes out transparent - which reads as black
        // the moment the PNG lands in a dark viewer.
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        ctx.scaleBy(x: s, y: s)

        // PDF space runs bottom-up, so the first page is drawn at the TOP by
        // starting from the total height and walking down.
        var y = height
        for (page, box) in zip(pages, boxes) {
            y -= box.height
            ctx.saveGState()
            ctx.translateBy(x: -box.minX, y: y - box.minY)
            ctx.drawPDFPage(page)
            ctx.restoreGState()
        }

        guard let image = ctx.makeImage() else { throw Failure.bitmap }
        return (image, s)
    }

    // MARK: - Write

    static func write(_ image: CGImage, to url: URL, format: Format) throws {
        switch format {
        case .png:
            try writePNG(image, to: url)
        case .webp:
            // cwebp reads a PNG and writes the WebP next to where it was asked to.
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            defer { try? FileManager.default.removeItem(at: temp) }
            try writePNG(image, to: temp)
            guard let encoder = webpEncoder else { throw Failure.encode("cwebp is not installed") }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: encoder)
            // -q 90 is visually lossless on flat note pages and roughly a third of
            // the PNG's size.
            task.arguments = ["-quiet", "-q", "90", temp.path, "-o", url.path]
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                throw Failure.encode("cwebp exited with code \(task.terminationStatus)")
            }
        }
    }

    static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encode("could not create the PNG")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure.encode("could not encode the PNG") }
        return data as Data
    }

    /// The bitmap injected into an SVG wrapper. The SVG is sized in points - what
    /// the note measures on screen - while the embedded PNG keeps its retina
    /// pixels, so a paste lands at the right size and stays sharp when scaled.
    static func svgDocument(png: Data, pixelWidth: Int, pixelHeight: Int, scale: CGFloat) -> String {
        let w = Int((CGFloat(pixelWidth) / scale).rounded())
        let h = Int((CGFloat(pixelHeight) / scale).rounded())
        return """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(w)" height="\(h)" viewBox="0 0 \(w) \(h)">
        <image width="\(w)" height="\(h)" xlink:href="data:image/png;base64,\(png.base64EncodedString())"/>
        </svg>
        """
    }

    // MARK: - Copy

    /// The whole note onto the clipboard in 3 flavours. The PDF is the vector
    /// WebKit laid out, so a canvas app that takes it stays sharp at any zoom.
    /// The SVG and PNG are rasters of the same page for the apps that do not.
    /// No save panel, so no empty message.
    @MainActor
    static func copy(from view: WKWebView?) async -> (Toast.Kind, String) {
        guard let view else { return (.failure, "No note is open") }
        do {
            let pdf = try await view.pdf(configuration: WKPDFConfiguration())
            let (image, scale) = try render(pdf: pdf, scale: 3)
            let png = try pngData(image)
            let svg = svgDocument(png: png, pixelWidth: image.width, pixelHeight: image.height, scale: scale)
            place(pdf: pdf, svg: Data(svg.utf8), png: png, on: .general)
            return (.success, "Note copied")
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (.failure, "Could not copy the note: \(reason)")
        }
    }

    static let svgType = NSPasteboard.PasteboardType(UTType.svg.identifier)

    static func place(pdf: Data, svg: Data, png: Data, on board: NSPasteboard) {
        board.clearContents()
        board.setData(pdf, forType: .pdf)
        board.setData(svg, forType: svgType)
        board.setData(png, forType: .png)
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.encode("could not create the PNG")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw Failure.encode("could not write the PNG") }
    }

    // MARK: - The whole flow

    /// Capture, ask where it goes, write it. Returns what to put in the toast, so
    /// the toolbar item and the menu item behave identically.
    @MainActor
    static func save(note title: String, from view: WKWebView?, format: Format) async -> (Toast.Kind, String) {
        guard let view else { return (.failure, "No note is open") }
        do {
            let image = try await fullPageImage(of: view)
            guard let url = destination(for: title, format: format, in: view.window) else {
                return (.success, "")          // cancelled - the caller drops an empty message
            }
            try write(image, to: url, format: format)
            return (.success, "Saved \(url.lastPathComponent)")
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return (.failure, "Could not save the image: \(reason)")
        }
    }

    // MARK: - Where to put it

    /// The save sheet, pre-filled with the note's title. Nil when it is cancelled.
    @MainActor
    static func destination(for title: String, format: Format, in window: NSWindow?) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeName(title)).\(format.ext)"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let type = UTType(filenameExtension: format.ext) { panel.allowedContentTypes = [type] }
        panel.message = "Save the whole note as one image"
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// A title is free text; a filename is not. Slashes and colons are the two
    /// that actually break a save, and a run of spaces reads better as one.
    static func safeName(_ title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = cleaned.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return collapsed.isEmpty ? "Note" : String(collapsed.prefix(80))
    }
}
