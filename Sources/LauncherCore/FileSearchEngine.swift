import Darwin
import Dispatch
import Synchronization

/// Owns the `FileIndex` on a private serial queue: patches from FSEvents and searches run there one at a time, so the
/// index needs no locks and the main thread never waits on it. Full scans run on a worker, and the result is swapped
/// in.
public final class FileSearchEngine: @unchecked Sendable {
    // State below is only touched on `queue`.
    private let queue = DispatchQueue(label: "launcher.files", qos: .userInitiated)
    private var index = FileIndex()
    private var rules: FileRules?
    private var boosts: [String: Int32] = [:]
    private var watcher: DirectoryWatcher?
    /// Events that arrive while a scan runs, applied once its index is swapped in.
    private var pendingEvents: [DirectoryWatcher.Event]?
    /// The newest search asked for; older ones still queued return nil without searching.
    private let latestSearch = Atomic<Int>(0)
    /// How many rebuilds were asked for. A rebuild that a newer one overtakes stops, or drops its scan.
    private let rebuilds = Atomic<Int>(0)
    private let onRemoved: @Sendable ([String]) -> Void

    /// `onRemoved` gets the files and folders that disappeared from disk (folders stand for everything in them), on
    /// the engine's queue.
    public init(onRemoved: @escaping @Sendable ([String]) -> Void = { _ in }) {
        self.onRemoved = onRemoved
    }

    /// Scans `rules` into a fresh index on a worker, swaps it in, and keeps it current with FSEvents from then on. The
    /// old index keeps answering searches meanwhile. The newest rebuild asked for wins: an older scan that finishes
    /// after it is dropped, so it can't put back folders the config no longer lists.
    public func rebuild(_ rules: FileRules) async {
        let generation = rebuilds.wrappingAdd(1, ordering: .relaxed).newValue
        let isNewest = await run { [self] () -> Bool in
            guard rebuilds.load(ordering: .relaxed) == generation else { return false }
            self.rules = rules
            pendingEvents = []
            watcher = DirectoryWatcher(
                paths: rules.roots, excluding: rules.ignore.paths, fileEvents: true, latency: 0.5, queue: queue
            ) { [weak self] events in self?.receive(events) }
            return true
        }
        guard isNewest else { return }
        let fresh = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var fresh = FileIndex()
                FileScanner.scan(rules, into: &fresh)
                fresh.trim()
                continuation.resume(returning: fresh)
            }
        }
        await run { [self] in
            guard rebuilds.load(ordering: .relaxed) == generation else { return }
            index = fresh
            index.setBoosts(boosts)
            let events = pendingEvents ?? []
            pendingEvents = nil
            apply(events)
        }
    }

    /// The history's boosts by path. Kept across rebuilds.
    public func setBoosts(_ byPath: [String: Int32]) {
        queue.async { [self] in
            boosts = byPath
            index.setBoosts(byPath)
        }
    }

    /// The best matches for `query`, or nil if a newer search (`generation`) was asked for before this one started.
    public func search(_ query: String, limit: Int, generation: Int) async -> [FileHit]? {
        // Relaxed is enough: the value only lets stale searches skip their work.
        latestSearch.store(generation, ordering: .relaxed)
        return await run { [self] in
            guard latestSearch.load(ordering: .relaxed) == generation else { return nil }
            return index.search(query, limit: limit)
        }
    }

    public var count: Int {
        get async { await run { [self] in index.count } }
    }

    /// How many rebuilds were asked for, for tests to order them.
    var rebuildsAsked: Int { rebuilds.load(ordering: .relaxed) }

    /// Runs `work` on the queue, which owns the index.
    func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: Live updates (on `queue`)

    private func receive(_ events: [DirectoryWatcher.Event]) {
        if pendingEvents != nil {
            pendingEvents?.append(contentsOf: events)
        } else {
            apply(events)
        }
    }

    /// Patches the index from FSEvents. Paths outside it are skipped without touching the disk; the rest are checked
    /// with one `lstat`, which makes repeated or out-of-order events harmless.
    private func apply(_ events: [DirectoryWatcher.Event]) {
        guard let rules, !events.isEmpty else { return }
        var removed: [String] = []
        for event in events {
            var path = event.path
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }

            if event.mustRescan {
                rescan(path, rules: rules)
                continue
            }
            let known = index.contains(path)
            guard known || index.entry(at: Self.parent(of: path)) != nil else { continue }

            var info = stat()
            guard lstat(path, &info) == 0, !rules.ignore.ignores(name: Self.name(of: path), path: path) else {
                if known {
                    index.remove(path)
                    removed.append(path)
                }
                continue
            }
            let isFolder = info.st_mode & S_IFMT == S_IFDIR && !FileScanner.isPackage(path)
            if known, index.isFolder(path) == isFolder { continue }
            if known { index.remove(path) }  // a file replaced by a folder, or the other way around
            // A folder that appears (created, moved in, restored) is indexed with what's in it.
            if index.insert(path, isFolder: isFolder, maxDepth: rules.maxDepth), isFolder {
                FileScanner.scan(folder: path, rules: rules, into: &index)
            }
        }
        if !removed.isEmpty { onRemoved(removed) }
    }

    /// Events under `path` were dropped: index it again from disk.
    private func rescan(_ path: String, rules: FileRules) {
        if rules.roots.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) {
            var fresh = FileIndex()
            FileScanner.scan(rules, into: &fresh)
            fresh.trim()
            index = fresh
            index.setBoosts(boosts)
        } else if index.isFolder(path) == true {
            index.removeDescendants(of: path)
            FileScanner.scan(folder: path, rules: rules, into: &index)
        }
    }

    private static func parent(of path: String) -> String {
        path.lastIndex(of: "/").map { String(path[..<$0]) } ?? path
    }

    private static func name(of path: String) -> String {
        String(FileIndex.name(of: path))
    }
}
