import AppKit
import ImageIO
import LauncherCore

/// Copied images' thumbnails as decoded bitmaps, read from the store's files on a worker (`docs/MILESTONE-3.md` step 4).
///
/// The newest clips' are loaded as soon as they're recorded, so ⌘⇧V draws without touching the disk; older ones load
/// when a row or the tile first asks, and show once ready. Row thumbnails are small (40 px, 6 KB) and kept; previews
/// (up to 640 × 312 px, 800 KB) are kept for the few most recently shown.
final class ClipImages {
    /// How many of the newest clips have their thumbnails ready ahead of time: the five rows and a little scrolling.
    static let preloaded = 12
    static let previewsKept = 8

    private var rows: [Int64: CGImage] = [:]
    private var previews: [Int64: CGImage] = [:]
    /// Most recently used last.
    private var previewOrder: [Int64] = []
    private var loading: Set<Key> = []
    /// Thumbnails that couldn't be read (a file gone): asked for once, so a row that redraws doesn't ask again.
    private var failed: Set<Key> = []

    private struct Key: Hashable {
        var id: Int64
        var preview: Bool
    }

    /// Whether thumbnails are being read.
    var isLoading: Bool { !loading.isEmpty }

    /// Called on the main thread when new bitmaps are ready.
    var onChange: (() -> Void)?

    func row(_ clip: Clip, store: ClipboardStore) -> CGImage? {
        if let image = rows[clip.id] { return image }
        load([clip], previews: false, store: store)
        return nil
    }

    func preview(_ clip: Clip, store: ClipboardStore) -> CGImage? {
        if let image = previews[clip.id] {
            previewOrder.removeAll { $0 == clip.id }
            previewOrder.append(clip.id)
            return image
        }
        load([clip], previews: true, store: store)
        return nil
    }

    /// Readies the newest image clips' thumbnails, and forgets those of clips no longer in the history.
    func preload(_ index: ClipboardIndex, store: ClipboardStore) {
        let ids = Set(index.clips.lazy.map(\.id))
        rows = rows.filter { ids.contains($0.key) }
        previews = previews.filter { ids.contains($0.key) }
        previewOrder.removeAll { !ids.contains($0) }
        failed = failed.filter { ids.contains($0.id) }
        let newest = index.clips.prefix(Self.preloaded).filter { $0.kind == .image }
        load(newest, previews: false, store: store)
        load(newest.prefix(3), previews: true, store: store)
    }

    private func load(_ clips: some Collection<Clip>, previews wantPreviews: Bool, store: ClipboardStore) {
        let missing = clips.filter { clip in
            let key = Key(id: clip.id, preview: wantPreviews)
            return clip.kind == .image && (wantPreviews ? previews[clip.id] : rows[clip.id]) == nil
                && !loading.contains(key) && !failed.contains(key)
        }
        guard !missing.isEmpty else { return }
        let keys = missing.map { Key(id: $0.id, preview: wantPreviews) }
        loading.formUnion(keys)
        let files = missing.map { wantPreviews ? store.previewThumbnail(of: $0.id) : store.rowThumbnail(of: $0.id) }
        Task {
            let images = await runInBackground(qos: .userInitiated) { files.map(Self.decode) }
            loading.subtract(keys)
            var loaded = false
            for (key, image) in zip(keys, images) {
                guard let image else {
                    failed.insert(key)
                    continue
                }
                loaded = true
                let id = key.id
                if wantPreviews {
                    previews[id] = image
                    previewOrder.append(id)
                } else {
                    rows[id] = image
                }
            }
            while previewOrder.count > Self.previewsKept { previews[previewOrder.removeFirst()] = nil }
            // Only when there's something new to draw: a redraw asks for the rows' thumbnails again.
            if loaded { onChange?() }
        }
    }

    /// The file's image, decoded now rather than when first drawn.
    private nonisolated static func decode(_ file: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(
            source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
