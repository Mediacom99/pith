import Dispatch
import Synchronization

/// Owns the `FileIndex` on a private serial queue: scans, patches and searches run there one at a time, so the index
/// needs no locks and the main thread never waits on it.
public final class FileSearchEngine: @unchecked Sendable {
    // State below is only touched on `queue`.
    private let queue = DispatchQueue(label: "launcher.files", qos: .userInitiated)
    private var index = FileIndex()
    private var rules: FileRules?
    private var boosts: [String: Int32] = [:]
    /// The newest search asked for; older ones still queued return nil without searching.
    private let latestSearch = Atomic<Int>(0)

    public init() {}

    /// Scans `rules` into a fresh index and swaps it in. The old index keeps answering searches meanwhile.
    public func rebuild(_ rules: FileRules) async {
        let fresh = await run(qos: .utility) {
            var fresh = FileIndex()
            FileScanner.scan(rules, into: &fresh)
            fresh.trim()
            return fresh
        }
        await run { [self] in
            index = fresh
            index.setBoosts(boosts)
            self.rules = rules
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

    /// Runs `work` on the queue, which owns the index.
    func run<T: Sendable>(qos: DispatchQoS = .unspecified, _ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async(qos: qos) { continuation.resume(returning: work()) }
        }
    }

    /// For the live updates (`apply`), which need both.
    func withIndex<T: Sendable>(_ work: @escaping @Sendable (inout FileIndex, FileRules?) -> T) async -> T {
        await run { [self] in work(&index, rules) }
    }
}
