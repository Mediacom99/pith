import AppKit
import UniformTypeIdentifiers

/// The two sizes icons come in: the list's rows and the tile.
nonisolated enum IconSize: Sendable, CaseIterable {
    case row, tile
}

/// A symbol's color: quiet like the folders, orange for a config problem, red for Force Quit's second ⏎.
nonisolated enum SymbolTint: Sendable {
    case quiet, warning, danger
}

/// Icons as bitmaps at their exact on-screen pixel size, in both sizes, rendered off the main thread: app icons in
/// parallel, file icons by type, and the SF Symbols used by commands, actions and problems.
///
/// Drawing an app icon for the first time costs ~5 ms (up to ~40 ms), so it must never happen on the main thread
/// while you type. Rows and the tile only display ready bitmaps; until a batch lands, they show no icon. 111 apps take
/// ~4.8 MB at 2×: 0.7 MB for the rows, 4.1 MB for the tile. Everything is re-rendered when the light/dark appearance or
/// the system icon style (Default, Dark, Clear, Tinted) changes.
final class IconStore {
    /// Posted by AppKit when the icon style changes. Private, found in AppKit; if it ever stops being posted, icons
    /// still update on the next appearance change.
    private static let iconStyleChanged = Notification.Name(
        "NSWorkspaceIconAppearanceConfigurationDidChangeNotification")

    /// One icon in both sizes.
    private struct Pair {
        var row: CGImage?
        var tile: CGImage?

        subscript(size: IconSize) -> CGImage? { size == .row ? row : tile }
    }

    private struct SymbolKey: Hashable {
        let name: String
        let tint: SymbolTint
        let size: IconSize
    }

    private var apps: [URL: Pair] = [:]
    private var symbols: [SymbolKey: CGImage] = [:]
    /// File and folder icons by type (`IconSource.key`), rendered on first request, and the type's name.
    private var types: [String: Pair] = [:]
    private var typeNames: [String: String] = [:]
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

    func icon(for url: URL, size: IconSize = .row) -> CGImage? {
        apps[url]?[size]
    }

    func symbol(_ name: String, tint: SymbolTint = .quiet, size: IconSize = .row) -> CGImage? {
        symbols[SymbolKey(name: name, tint: tint, size: size)]
    }

    /// A file's or folder's icon by its type (an app bundle's own icon), or nil until it's rendered: the first
    /// request queues it, and `onChange` reports it ready.
    func icon(forFile url: URL, size: IconSize = .row) -> CGImage? {
        let source = IconSource(url)
        if let icon = types[source.key] { return icon[size] }
        if !renderingTypes.contains(source.key), requestedTypes.insert(source.key).inserted, requestedTypes.count == 1 {
            // Collects the rows configured in this pass, then renders them in one batch.
            Task { @MainActor in renderRequestedTypes() }
        }
        return nil
    }

    /// What macOS calls a file's type ("PDF document"), once its icon is rendered.
    func typeName(forFile url: URL) -> String? {
        typeNames[IconSource(url).key]
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
            let rendered = await runInBackground(qos: .userInitiated) {
                keys.map { key in
                    let source = IconSource(key: key)
                    let icon = source.icon()
                    let images = pixels.map { pixels in
                        Self.bitmap(pixels: pixels, appearance: appearance) { icon.draw(in: $0) }
                    }
                    return (Pair(row: images[0], tile: images[1]), source.typeName())
                }
            }
            guard style == self.style else { return }
            renderingTypes.subtract(keys)
            for (key, (icon, name)) in zip(keys, rendered) {
                types[key] = icon
                typeNames[key] = name
            }
            onChange?()
        }
    }

    /// Each size's width in pixels, on the sharpest screen attached: rows, then the tile.
    private static var pixels: [Int] {
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        return [Int(Layout.iconSize * scale), Int(Layout.tileIconSize * scale)]
    }
    private static var appearance: NSAppearance.Name {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
    }

    /// Keeps icons for `urls` only and renders the missing ones (and the symbols, the first time).
    func load(_ urls: Set<URL>) {
        wanted = urls
        apps = apps.filter { urls.contains($0.key) }
        let missing = urls.filter { apps[$0] == nil && !rendering.contains($0) }
        render(Array(missing), symbols: symbolsRequested ? [] : Symbols.rendered)
        symbolsRequested = true
    }

    private func restyle() {
        style += 1
        rendering = []
        renderingTypes = []
        Log.perf.debug("Appearance or icon style changed: re-rendering \(self.wanted.count) icons")
        render(Array(wanted), symbols: Symbols.rendered)
        renderTypes(Array(types.keys))
    }

    private func render(_ urls: [URL], symbols wantedSymbols: [(name: String, tint: SymbolTint, size: IconSize)]) {
        guard !urls.isEmpty || !wantedSymbols.isEmpty else { return }
        rendering.formUnion(urls)
        let style = self.style
        let pixels = Self.pixels
        let appearance = Self.appearance
        Task {
            let (icons, glyphs) = await runInBackground(qos: .userInitiated) {
                (
                    Self.renderApps(urls, pixels: pixels, appearance: appearance),
                    wantedSymbols.map { symbol in
                        Self.renderSymbol(
                            symbol.name, tint: symbol.tint, pixels: pixels[symbol.size == .row ? 0 : 1],
                            appearance: appearance)
                    }
                )
            }
            guard style == self.style else { return }
            rendering.subtract(urls)
            for (url, icon) in zip(urls, icons) where wanted.contains(url) {
                apps[url] = icon
            }
            for (symbol, glyph) in zip(wantedSymbols, glyphs) {
                symbols[SymbolKey(name: symbol.name, tint: symbol.tint, size: symbol.size)] = glyph
            }
            onChange?()
        }
    }

    /// One icon per core at a time: each is independent, and IconServices renders them in parallel.
    private nonisolated static func renderApps(_ urls: [URL], pixels: [Int], appearance: NSAppearance.Name) -> [Pair] {
        var images = [Pair](repeating: Pair(), count: urls.count)
        images.withUnsafeMutableBufferPointer { buffer in
            // Each iteration writes only its own slot, so sharing the buffer across threads is safe.
            nonisolated(unsafe) let slots = buffer
            DispatchQueue.concurrentPerform(iterations: urls.count) { index in
                let icon = NSWorkspace.shared.icon(forFile: urls[index].path)
                let images = pixels.map { pixels in bitmap(pixels: pixels, appearance: appearance) { icon.draw(in: $0) }
                }
                slots[index] = Pair(row: images[0], tile: images[1])
            }
        }
        return images
    }

    /// A symbol, centered, in its tint.
    private nonisolated static func renderSymbol(
        _ name: String, tint: SymbolTint, pixels: Int, appearance: NSAppearance.Name
    ) -> CGImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(pixels) * 0.62, weight: .regular)
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
            // Source-in keeps the glyph's shape and takes the color, alpha included.
            let color =
                switch tint {
                case .quiet: Palette.quiet
                case .warning: Palette.warning
                case .danger: Palette.danger
                }
            color.set()
            canvas.fill(using: .sourceIn)
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

    /// What macOS calls the type, capitalized ("PDF document", "Folder"). Asks LaunchServices: call on a worker.
    func typeName() -> String {
        let name: String? =
            if key == "folder" {
                UTType.folder.localizedDescription
            } else if key.hasPrefix("path:") {
                UTType.application.localizedDescription
            } else {
                UTType(filenameExtension: String(key.dropFirst(4)))?.localizedDescription
            }
        guard let name, let first = name.first else { return "Document" }
        return first.uppercased() + name.dropFirst()
    }

    /// Asks IconServices: call on a worker.
    func icon() -> NSImage {
        if key == "folder" { return NSWorkspace.shared.icon(for: .folder) }
        if key.hasPrefix("path:") { return NSWorkspace.shared.icon(forFile: String(key.dropFirst(5))) }
        let ext = String(key.dropFirst(4))
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }
}
