import Foundation
import LauncherCore

/// Whether the files a clip names are still there, and their size, for the clipboard's tile. A clip's paths are read
/// together, in one job on a worker, the first time the tile shows it after the clipboard opens: a copied file can be
/// deleted or change size meanwhile. The last answer shows while the new one is read, and the tile is told once, when
/// the answer changed.
final class FileFacts {
    /// One path: whether it's there, and its size, nil for a folder (whose own size isn't its contents').
    typealias Fact = (exists: Bool, bytes: Int?)

    /// What the tile says about a clip's files.
    struct Summary: Equatable {
        /// The first file is still there.
        var firstExists: Bool
        /// All of them together, nil when one is a folder or the list in memory is cut short.
        var bytes: Int?
    }

    /// Reads one path's fact. Blocking (the file system): runs on a worker. Snapshots fix it.
    var read: @Sendable (String) -> Fact = { path in
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return (false, nil) }
        if attributes[.type] as? FileAttributeType == .typeDirectory { return (true, nil) }
        return (true, (attributes[.size] as? NSNumber)?.intValue)
    }
    /// Called on the main thread when a summary read again differs from the one shown.
    var onChange: (() -> Void)?

    private var known: [Int64: Summary] = [:]
    /// Read since the clipboard last opened.
    private var fresh: Set<Int64> = []
    private var loading: Set<Int64> = []

    /// The clipboard opened: each clip is read again the next time it's shown.
    func markStale() {
        fresh = []
    }

    /// What's known about `clip`'s files, nil until its first read lands. Starts a read when it isn't fresh.
    func summary(of clip: Clip) -> Summary? {
        if !fresh.contains(clip.id), loading.insert(clip.id).inserted {
            let read = self.read
            Task {
                let summary = await runInBackground(qos: .userInitiated) { Self.summarize(clip, read: read) }
                loading.remove(clip.id)
                fresh.insert(clip.id)
                let changed = known[clip.id] != summary
                known[clip.id] = summary
                if changed { onChange?() }
            }
        }
        return known[clip.id]
    }

    /// Reads every path of `clip` in memory. Blocking: on a worker.
    private nonisolated static func summarize(_ clip: Clip, read: (String) -> Fact) -> Summary {
        let paths = ClipText.paths(of: clip)
        var total: Int? = clip.text.utf8.count < clip.textBytes ? nil : 0
        var firstExists = false
        var anyExists = false
        for (position, path) in paths.enumerated() {
            let fact = read(path)
            if position == 0 { firstExists = fact.exists }
            guard fact.exists else { continue }
            anyExists = true
            if let bytes = fact.bytes { total = total.map { $0 + bytes } } else { total = nil }
        }
        return Summary(firstExists: firstExists, bytes: anyExists ? total : nil)
    }
}
