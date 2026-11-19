import AppKit
import UniformTypeIdentifiers

/// Row icons as bitmaps at their exact on-screen pixel size, rendered off the main thread: app icons in parallel, and
/// the SF Symbols used by commands and actions.
///
/// Drawing an app icon for the first time costs ~5 ms (up to ~40 ms), so it must never happen on the main thread
/// while you type. Rows only display ready bitmaps; until a batch lands, a row shows no icon. 113 apps take ~1.4 MB.
/// Everything is re-rendered when the light/dark appearance or the system icon style (Default, Dark, Clear, Tinted)
/// changes.
final class IconStore {
    /// Posted by AppKit when the icon style changes. Private, found in AppKit; if it ever stops being posted, icons
    /// still update on the next appearance change.
    private static let iconStyleChanged = Notification.Name(
        "NSWorkspaceIconAppearanceConfigurationDidChangeNotification")

    private var apps: [URL: CGImage] = [:]
    private var symbols: [String: CGImage] = [:]
    /// File and folder icons by type (`IconSource.key`), rendered on first request.
    private var types: [String: CGImage] = [:]
    private var requestedTypes: Set<String> = []
    private var renderingTypes: Set<String> = []
    private var wanted: Set<URL> = []
    private var rendering: Set<URL> = []
    private var symbolsRequested = false
    /// Bumped on every appearance or icon style change; renders started before it are dropped.
    private var style = 0
    private var appearanceObservation: NSKeyValueObservation?
    private var iconStyleObservers: [any NSObjectProtocol] = []

    /// Called on the main thread when new bitmaps are ready.
    var onChange: (() -> Void)?

    init() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.restyle() }
        }
        // Which center AppKit posts it on isn't documented: listen on both.
        iconStyleObservers = [NSWorkspace.shared.notificationCenter, NotificationCenter.default].map { center in
            center.addObserver(forName: Self.iconStyleChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.restyle() }
            }
        }
    }

    func icon(for url: URL) -> CGImage? {
        apps[url]
    }

    func symbol(_ name: String) -> CGImage? {
        symbols[name]
    }

    /// A file's or folder's icon by its type (an app bundle's own icon), or nil until it's rendered: the first
    /// request queues it, and `onChange` reports it ready.
    func icon(forFile url: URL) -> CGImage? {
        let source = IconSource(url)
        if let icon = types[source.key] { return icon }
        if !renderingTypes.contains(source.key), requestedTypes.insert(source.key).inserted, requestedTypes.count == 1 {
            // Collects the rows configured in this pass, then renders them in one batch.
            Task { @MainActor in renderRequestedTypes() }
        }
        return nil
    }

    private func renderRequestedTypes() {
        let keys = Array(requestedTypes)
        requestedTypes = []
        renderTypes(keys)
    }

    private func renderTypes(_ keys: [String]) {
        guard !keys.isEmpty else { return }
        renderingTypes.formUnion(keys)
        let style = self.style
        let pixels = Self.pixels
        let appearance = Self.appearance
        Task {
            let icons = await runInBackground(qos: .userInitiated) {
                keys.map { key in
                    let icon = IconSource(key: key).icon()
                    return Self.bitmap(pixels: pixels, appearance: appearance) { icon.draw(in: $0) }
                }
            }
            guard style == self.style else { return }
            renderingTypes.subtract(keys)
            for (key, icon) in zip(keys, icons) { types[key] = icon }
            onChange?()
        }
    }

    private static var pixels: Int { Int(Layout.iconSize * (NSScreen.screens.map(\.backingScaleFactor).max() ?? 2)) }
    private static var appearance: NSAppearance.Name {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
    }

    /// Keeps icons for `urls` only and renders the missing ones (and the symbols, the first time).
    func load(_ urls: Set<URL>) {
        wanted = urls
        apps = apps.filter { urls.contains($0.key) }
        let missing = urls.filter { apps[$0] == nil && !rendering.contains($0) }
        render(Array(missing), symbols: symbolsRequested ? [] : Symbols.all)
        symbolsRequested = true
    }

    private func restyle() {
        style += 1
        rendering = []
        renderingTypes = []
        Log.perf.debug("Appearance or icon style changed: re-rendering \(self.wanted.count) icons")
        render(Array(wanted), symbols: Symbols.all)
        renderTypes(Array(types.keys))
    }

    private func render(_ urls: [URL], symbols names: [String]) {
        guard !urls.isEmpty || !names.isEmpty else { return }
        rendering.formUnion(urls)
        let style = self.style
        let pixels = Self.pixels
        let appearance = Self.appearance
        Task {
            let (icons, glyphs) = await runInBackground(qos: .userInitiated) {
                (
                    Self.renderApps(urls, pixels: pixels, appearance: appearance),
                    names.map { Self.renderSymbol($0, pixels: pixels, appearance: appearance) }
                )
            }
            guard style == self.style else { return }
            rendering.subtract(urls)
            for (url, icon) in zip(urls, icons) where wanted.contains(url) {
                apps[url] = icon
            }
            for (name, glyph) in zip(names, glyphs) {
                symbols[name] = glyph
            }
            onChange?()
        }
    }

    /// One icon per core at a time: each is independent, and IconServices renders them in parallel.
    private nonisolated static func renderApps(_ urls: [URL], pixels: Int, appearance: NSAppearance.Name) -> [CGImage?]
    {
        var images = [CGImage?](repeating: nil, count: urls.count)
        images.withUnsafeMutableBufferPointer { buffer in
            // Each iteration writes only its own slot, so sharing the buffer across threads is safe.
            nonisolated(unsafe) let slots = buffer
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                let icon = NSWorkspace.shared.icon(forFile: urls[index].path)
                slots[index] = bitmap(pixels: pixels, appearance: appearance) { icon.draw(in: $0) }
            }
        }
        return images
    }

    /// A symbol in the secondary label color, centered.
    private nonisolated static func renderSymbol(_ name: String, pixels: Int, appearance: NSAppearance.Name) -> CGImage?
    {
        let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(pixels) * 0.5, weight: .regular)
        guard
            let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else { return nil }
        return bitmap(pixels: pixels, appearance: appearance) { canvas in
            let size = symbol.size
            symbol.draw(
                in: NSRect(
                    x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2, width: size.width,
                    height: size.height))
            NSColor.secondaryLabelColor.set()
            canvas.fill(using: .sourceAtop)
        }
    }

    /// Draws into a fresh BGRA bitmap (the layout the compositor uses, so displaying it needs no conversion), under
    /// the given appearance. The current graphics context and appearance are per thread, so this is safe on a worker.
    private nonisolated static func bitmap(
        pixels: Int, appearance: NSAppearance.Name, draw: (NSRect) -> Void
    ) -> CGImage? {
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
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        if let appearance = NSAppearance(named: appearance) {
            appearance.performAsCurrentDrawingAppearance { draw(canvas) }
        } else {
            draw(canvas)
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

/// Where a file's icon comes from: folders share one, files share one per extension, and app bundles have their own.
nonisolated struct IconSource {
    let key: String

    init(_ url: URL) {
        if url.hasDirectoryPath {
            key = "folder"
        } else if url.pathExtension.lowercased() == "app" {
            key = "path:" + url.path
        } else {
            key = "ext:" + url.pathExtension.lowercased()
        }
    }

    init(key: String) {
        self.key = key
    }

    /// Asks IconServices: call on a worker.
    func icon() -> NSImage {
        if key == "folder" { return NSWorkspace.shared.icon(for: .folder) }
        if key.hasPrefix("path:") { return NSWorkspace.shared.icon(forFile: String(key.dropFirst(5))) }
        let ext = String(key.dropFirst(4))
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }
}
