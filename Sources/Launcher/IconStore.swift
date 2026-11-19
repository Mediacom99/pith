import AppKit

/// App icons as bitmaps at their exact on-screen pixel size, rendered once, in parallel, off the main thread.
///
/// Drawing an app icon for the first time costs ~5 ms (up to ~40 ms), so it must never happen on the main thread
/// while you type. Rows only display ready bitmaps; until a batch lands, a row shows no icon. 113 apps take ~1.4 MB.
final class IconStore {
    private var icons: [URL: CGImage] = [:]
    private var wanted: Set<URL> = []
    private var rendering: Set<URL> = []

    func icon(for url: URL) -> CGImage? {
        icons[url]
    }

    /// Keeps icons for `urls` only and renders the missing ones; `completion` runs once they're in.
    func load(_ urls: [URL], completion: @escaping () -> Void) {
        wanted = Set(urls)
        icons = icons.filter { wanted.contains($0.key) }
        let missing = urls.filter { icons[$0] == nil && !rendering.contains($0) }
        guard !missing.isEmpty else { return }
        rendering.formUnion(missing)
        let pixels = Int(Layout.iconSize * (NSScreen.screens.map(\.backingScaleFactor).max() ?? 2))
        Task {
            let images = await runInBackground(qos: .userInitiated) { Self.render(missing, pixels: pixels) }
            rendering.subtract(missing)
            for (url, image) in zip(missing, images) where wanted.contains(url) {
                icons[url] = image
            }
            completion()
        }
    }

    /// One icon per core at a time: each is independent, and IconServices renders them in parallel.
    private nonisolated static func render(_ urls: [URL], pixels: Int) -> [CGImage?] {
        var images = [CGImage?](repeating: nil, count: urls.count)
        images.withUnsafeMutableBufferPointer { buffer in
            // Each iteration writes only its own slot, so sharing the buffer across threads is safe.
            nonisolated(unsafe) let slots = buffer
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                slots[index] = renderIcon(atPath: urls[index].path, pixels: pixels)
            }
        }
        return images
    }

    private nonisolated static func renderIcon(atPath path: String, pixels: Int) -> CGImage? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        // BGRA, premultiplied: the layout the compositor uses, so displaying it needs no conversion.
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: pixels,
                height: pixels,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return nil }
        // The current graphics context is per thread, so this is safe on a worker.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
