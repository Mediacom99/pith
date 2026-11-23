import Darwin
import Dispatch
import Foundation
import Synchronization

/// Owns the `FileIndex` on a private serial queue: patches from FSEvents and searches run there one at a time, so the
/// index needs no locks and the main thread never waits on it. Full scans run on a worker, and the result is swapped
/// in.
///
/// The folders macOS asks about (`FileRules.protected`, decision 60) are each read once on a worker of their own, which
/// shows the prompt and waits for the answer. The index leaves out a folder until it's allowed, so the rest is
/// searchable at once, and is rebuilt with it as soon as it is. A refused folder is read again as the panel opens
/// (`recheckRefused`): it doesn't ask again, and once allowed in System Settings it joins the index.
public final class FileSearchEngine: @unchecked Sendable {
    /// What macOS said about a protected folder.
    private enum Access { case asking, allowed, refused }

    // State below is only touched on `queue`.
    private let queue = DispatchQueue(label: "launcher.files", qos: .userInitiated)
    private var index = FileIndex()
    /// The rules as asked for, and as scanned: without the protected folders that aren't allowed yet.
    private var requested: FileRules?
    private var rules: FileRules?
    private var access: [String: Access] = [:]
    /// The protected folders the index leaves out.
    private var deferred: Set<String> = []
    private var boosts: [String: Int32] = [:]
    private var watcher: DirectoryWatcher?
    /// Events that arrive while a scan runs, applied once its index is swapped in.
    private var pendingEvents: [DirectoryWatcher.Event]?
    /// The newest search asked for; older ones still queued return nil without searching.
    private let latestSearch = Atomic<Int>(0)
    /// How many rebuilds were asked for. A rebuild that a newer one overtakes stops, or drops its scan.
    private let rebuilds = Atomic<Int>(0)
    private let onRemoved: @Sendable ([String]) -> Void
    private let canRead: @Sendable (String) -> Bool

    /// `onRemoved` gets the files and folders that disappeared from disk (folders stand for everything in them), on
    /// the engine's queue. `canRead` reads a protected folder, waiting on its prompt; tests swap it.
    public init(
        onRemoved: @escaping @Sendable ([String]) -> Void = { _ in },
        canRead: @escaping @Sendable (String) -> Bool = FileSearchEngine.canRead
    ) {
        self.canRead = canRead
        self.onRemoved = onRemoved
    }

    /// Whether this process may list `folder`. The first time, macOS shows its prompt and the call waits for the
    /// answer; after that it answers at once. A folder that isn't there has nothing to ask about.
    public static func canRead(_ folder: String) -> Bool {
        guard let directory = opendir(folder) else { return errno == ENOENT }
        closedir(directory)
        return true
    }

    /// Scans `rules` into a fresh index on a worker, swaps it in, and keeps it current with FSEvents from then on. The
    /// old index keeps answering searches meanwhile. The newest rebuild asked for wins: an older scan that finishes
    /// after it is dropped, so it can't put back folders the config no longer lists.
    public func rebuild(_ rules: FileRules) async {
        let generation = rebuilds.wrappingAdd(1, ordering: .relaxed).newValue
        // Asked first, so the folders already answered are in this scan; one whose prompt is up joins later.
        await ask(about: rules.protectedFolders, waiting: .milliseconds(100))
        let planned = await run { [self] () -> FileRules? in
            guard rebuilds.load(ordering: .relaxed) == generation else { return nil }
            return rules.deferring(Set(rules.protectedFolders.filter { access[$0] != .allowed }))
        }
        guard let planned else { return }
        let excluded = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { continuation.resume(returning: planned.watchExclusions()) }
        }
        let scanned = await run { [self] () -> FileRules? in
            guard rebuilds.load(ordering: .relaxed) == generation else { return nil }
            requested = rules
            deferred = Set(rules.protectedFolders.filter { access[$0] != .allowed })
            let scanned = rules.deferring(deferred)
            self.rules = scanned
            pendingEvents = []
            watcher = DirectoryWatcher(
                paths: scanned.roots, excluding: excluded, fileEvents: true, latency: 0.5, queue: queue
            ) { [weak self] events in self?.receive(events) }
            return scanned
        }
        guard let scanned else { return }
        let fresh = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var fresh = FileIndex()
                FileScanner.scan(scanned, into: &fresh)
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

    /// Reads the protected folders that were refused again, in case they've been allowed in System Settings since:
    /// called as the panel opens. A refused folder doesn't prompt again, so each answers at once, on a worker.
    public func recheckRefused() {
        queue.async { [self] in
            let refused = access.compactMap { $0.value == .refused ? $0.key : nil }
            if !refused.isEmpty { startAsking(refused, group: nil) }
        }
    }

    /// Reads each folder of `folders` that isn't allowed or being asked about, and returns once all are answered or
    /// `wait` has passed. An answer that comes later and allows a folder the index left out rebuilds it.
    private func ask(about folders: [String], waiting wait: DispatchTimeInterval) async {
        guard !folders.isEmpty else { return }
        let group = DispatchGroup()
        await run { [self] in
            startAsking(folders.filter { access[$0] == nil || access[$0] == .refused }, group: group)
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                _ = group.wait(timeout: .now() + wait)
                continuation.resume()
            }
        }
    }

    /// On `queue`: reads each of `folders` on a worker of its own, since a prompt can wait for minutes.
    private func startAsking(_ folders: [String], group: DispatchGroup?) {
        for folder in folders {
            access[folder] = .asking
            group?.enter()
            DispatchQueue.global(qos: .utility).async { [self] in
                let allowed = canRead(folder)
                queue.async { [self] in
                    access[folder] = allowed ? .allowed : .refused
                    if allowed, deferred.contains(folder), let requested {
                        deferred.remove(folder)
                        Task { await self.rebuild(requested) }
                    }
                    group?.leave()
                }
            }
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
    /// with one `lstat`, which makes repeated or out-of-order events harmless. A configured folder that's created,
    /// moved or removed, or events dropped at or above one, scans everything again on a worker, once per batch.
    private func apply(_ events: [DirectoryWatcher.Event]) {
        guard let rules, !events.isEmpty else { return }
        var removed: [String] = []
        var rebuildAll = false
        for event in events {
            var path = event.path
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            if rules.roots.contains(where: { IgnoreRules.holds(path, $0) }) {
                if event.mustRescan || event.isAddedRemovedOrMoved { rebuildAll = true }
                continue
            }
            if let gone = update(path, moved: event.isAddedRemovedOrMoved, rules: rules) { removed.append(gone) }
            // Events dropped under a folder: what's in it is read again.
            if event.mustRescan, index.isFolder(path) == true {
                index.removeDescendants(of: path)
                FileScanner.scan(folder: path, rules: rules, into: &index)
            }
        }
        if !removed.isEmpty { onRemoved(removed) }
        if rebuildAll, let requested { Task { await rebuild(requested) } }
    }

    /// Brings `path` in line with the disk: added, removed, or a file that became a folder. Returns it if it was
    /// removed. `moved` is an event that added, removed or renamed it.
    private func update(_ path: String, moved: Bool, rules: FileRules) -> String? {
        let known = index.contains(path)
        guard known || index.entry(at: Self.parent(of: path)) != nil else { return nil }
        var info = stat()
        // A rename that changes only the case of a name: the disk ignores case, so the old name still finds the file,
        // under its new name.
        let renamedCase = known && moved && Self.nameOnDisk(path).map { $0 != Self.name(of: path) } == true
        guard lstat(path, &info) == 0, !renamedCase,
            !rules.ignore(at: path).ignores(name: Self.name(of: path), path: path)
        else {
            guard known else { return nil }
            index.remove(path)
            return path
        }
        let isFolder = info.st_mode & S_IFMT == S_IFDIR && !FileScanner.isPackage(path)
        if known, index.isFolder(path) == isFolder { return nil }
        if known { index.remove(path) }  // a file replaced by a folder, or the other way around
        // A folder that appears (created, moved in, restored) is indexed with what's in it.
        if index.insert(path, isFolder: isFolder, maxDepth: rules.maxDepth), isFolder {
            FileScanner.scan(folder: path, rules: rules, into: &index)
        }
        return nil
    }

    private static func parent(of path: String) -> String {
        path.lastIndex(of: "/").map { String(path[..<$0]) } ?? path
    }

    private static func name(of path: String) -> String {
        String(FileIndex.name(of: path))
    }

    /// The name the disk has for `path`'s last part, in its own case; nil if there's nothing there.
    private static func nameOnDisk(_ path: String) -> String? {
        try? URL(filePath: path).resourceValues(forKeys: [.nameKey]).name
    }
}
