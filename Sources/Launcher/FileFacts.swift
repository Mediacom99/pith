import Foundation

/// Whether the files a clip names are still there, and their size, for the clipboard's tile. Each path is read on a
/// worker the first time the tile shows it after the clipboard opens: a copied file can be deleted or change size
/// meanwhile. The last answer shows while the new one is read.
final class FileFacts {
    typealias Fact = (exists: Bool, bytes: Int?)

    /// Reads one path's fact. Blocking (the file system): runs on a worker. Snapshots fix it.
    var read: @Sendable (String) -> Fact = { path in
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return (false, nil) }
        return (true, (attributes[.size] as? NSNumber)?.intValue)
    }
    /// Called on the main thread when a fact read again differs from the one shown.
    var onChange: (() -> Void)?

    private var known: [String: Fact] = [:]
    /// Read since the clipboard last opened.
    private var fresh: Set<String> = []
    private var loading: Set<String> = []

    /// The clipboard opened: each path is read again the next time it's shown.
    func markStale() {
        fresh = []
    }

    /// What's known about `path`, nil until its first read lands. Starts a read when it isn't fresh.
    func fact(for path: String) -> Fact? {
        if !fresh.contains(path), loading.insert(path).inserted {
            let read = self.read
            Task {
                let fact = await runInBackground(qos: .userInitiated) { read(path) }
                loading.remove(path)
                fresh.insert(path)
                let changed = known[path].map { $0.exists != fact.exists || $0.bytes != fact.bytes } ?? true
                known[path] = fact
                if changed { onChange?() }
            }
        }
        return known[path]
    }
}
