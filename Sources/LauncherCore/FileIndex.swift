import Dispatch
import Foundation

/// A file or folder that matched a search.
public struct FileHit: Sendable, Equatable {
    public let path: String
    public let isFolder: Bool
    /// Match score plus history boost, comparable with `SearchIndex` scores.
    public let score: Int32
}

/// The in-memory index of files and folders, matched by name.
///
/// Stored as a tree in flat arrays: each entry has its name (original UTF-8, in one shared buffer), its parent and
/// its search key, and folders list their children. A hash table finds a child by (parent, name) in O(1), so a path
/// resolves in one step per component. Full paths are rebuilt only for the results shown, so 35k entries take a few
/// MB. Removed entries are marked and skipped, and compacted away once they pile up. Not
/// thread-safe: one owner (`FileSearchEngine`) uses it from one queue.
public struct FileIndex: Sendable {
    private var names: [UInt8] = []
    /// Entry `i`'s name is `names[nameStarts[i] ..< nameStarts[i + 1]]`. A root's name is its absolute path.
    private var nameStarts: [UInt32] = [0]
    private var parents: [Int32] = []
    private var depths: [UInt8] = []
    private var flags: [UInt8] = []
    private var keys = KeyStore()
    /// The history's ranking boost per entry.
    private var boosts: [Int32] = []
    /// Children of each folder (and root) that has any. May still list removed entries, which are skipped and
    /// dropped at the next compaction, so removing is O(1).
    private var children: [Int32: [Int32]] = [:]
    /// Live entries by parent and name hash, so a path resolves in O(1) per component.
    private var lookup: [ChildKey: Int32] = [:]
    /// Keys two live children have shared (a hash collision, never seen in practice): only these fall back to
    /// scanning `children`.
    private var collisions: Set<ChildKey> = []
    private var roots: [(path: String, entry: Int32)] = []
    private var removedCount = 0
    private var rootCount = 0

    private static let folder: UInt8 = 1
    private static let removed: UInt8 = 2
    private static let root: UInt8 = 4
    private static let cores = ProcessInfo.processInfo.activeProcessorCount

    public init() {}

    /// Live entries, not counting roots.
    public var count: Int { flags.count - removedCount - rootCount }

    // MARK: Building

    /// Adds a folder to index under: not an entry of its own, never a result.
    @discardableResult
    public mutating func addRoot(_ path: String) -> Int32 {
        if let existing = roots.first(where: { $0.path == path }) { return existing.entry }
        let entry = append(name: path, parent: -1, depth: 0, flag: Self.root | Self.folder, searchable: false)
        roots.append((path, entry))
        rootCount += 1
        return entry
    }

    /// Adds `name` under `parent`, for scans of a folder whose children aren't indexed yet.
    @discardableResult
    mutating func add(name: String, parent: Int32, isFolder: Bool) -> Int32 {
        let entry = append(
            name: name, parent: parent, depth: depths[Int(parent)] &+ 1, flag: isFolder ? Self.folder : 0,
            searchable: true)
        children[parent, default: []].append(entry)
        let key = ChildKey(parent: parent, name: name.utf8)
        if lookup[key] == nil { lookup[key] = entry } else { collisions.insert(key) }
        return entry
    }

    /// Adds `path`, or updates whether it's a folder. Returns false if `path` is outside the index: not under a root,
    /// or its parent folder isn't indexed (ignored, or too deep).
    @discardableResult
    public mutating func insert(_ path: String, isFolder: Bool) -> Bool {
        if let entry = entry(at: path) {
            guard flags[Int(entry)] & Self.root == 0 else { return true }
            flags[Int(entry)] = (flags[Int(entry)] & ~Self.folder) | (isFolder ? Self.folder : 0)
            return true
        }
        guard let slash = path.lastIndex(of: "/"), let parent = entry(at: String(path[..<slash])),
            flags[Int(parent)] & Self.folder != 0
        else { return false }
        add(name: String(path[path.index(after: slash)...]), parent: parent, isFolder: isFolder)
        return true
    }

    /// Removes `path` and, if it's a folder, everything under it.
    public mutating func remove(_ path: String) {
        guard let entry = entry(at: path), flags[Int(entry)] & Self.root == 0 else { return }
        removeDescendants(of: entry)
        markRemoved(entry)
        compactIfNeeded()
    }

    /// Marks an entry removed and drops it from the lookup table.
    private mutating func markRemoved(_ entry: Int32) {
        guard flags[Int(entry)] & Self.removed == 0 else { return }
        flags[Int(entry)] |= Self.removed
        removedCount += 1
        let parent = parents[Int(entry)]
        let key = ChildKey(parent: parent, name: name(of: entry))
        guard lookup[key] == entry else { return }
        lookup[key] = nil
        // Another live child with the same key takes its place.
        if collisions.contains(key),
            let other = liveChildren(of: parent).first(where: { ChildKey(parent: parent, name: name(of: $0)) == key })
        {
            lookup[key] = other
        }
    }

    private func liveChildren(of folder: Int32) -> some Sequence<Int32> {
        (children[folder] ?? []).lazy.filter { flags[Int($0)] & Self.removed == 0 }
    }

    /// Removes everything under `folder`, but not the folder itself.
    public mutating func removeDescendants(of folder: String) {
        guard let entry = entry(at: folder) else { return }
        removeDescendants(of: entry)
        compactIfNeeded()
    }

    private mutating func removeDescendants(of entry: Int32) {
        guard let kids = children.removeValue(forKey: entry) else { return }
        for kid in kids {
            removeDescendants(of: kid)
            markRemoved(kid)
        }
    }

    /// Replaces every boost: `byPath` gives the boost for each path that has one.
    public mutating func setBoosts(_ byPath: [String: Int32]) {
        for index in boosts.indices { boosts[index] = 0 }
        for (path, boost) in byPath {
            if let entry = entry(at: path) { boosts[Int(entry)] = boost }
        }
    }

    // MARK: Looking up

    /// The entry for an absolute path, walking down from its root one name at a time.
    public func entry(at path: String) -> Int32? {
        guard
            let root = roots.filter({ path == $0.path || path.hasPrefix($0.path + "/") })
                .max(by: { $0.path.count < $1.path.count })
        else { return nil }
        var current = root.entry
        for component in path.dropFirst(root.path.count).split(separator: "/") {
            let utf8 = component.utf8
            let key = ChildKey(parent: current, name: utf8)
            if let match = lookup[key], name(of: match).elementsEqual(utf8) {
                current = match
            } else if collisions.contains(key),
                let match = liveChildren(of: current).first(where: { name(of: $0).elementsEqual(utf8) })
            {
                current = match
            } else {
                return nil
            }
        }
        return current
    }

    public func contains(_ path: String) -> Bool {
        entry(at: path).map { flags[Int($0)] & Self.root == 0 } ?? false
    }

    public func isFolder(_ path: String) -> Bool? {
        entry(at: path).flatMap { flags[Int($0)] & Self.root == 0 ? flags[Int($0)] & Self.folder != 0 : nil }
    }

    /// How many folders below its root an entry is: 1 for a root's direct contents.
    func depth(of entry: Int32) -> Int {
        Int(depths[Int(entry)])
    }

    public func path(of entry: Int32) -> String {
        var chain: [Int32] = []
        var current = entry
        while current >= 0 {
            chain.append(current)
            current = parents[Int(current)]
        }
        var bytes: [UInt8] = []
        for (offset, link) in chain.reversed().enumerated() {
            if offset > 0 { bytes.append(UInt8(ascii: "/")) }
            bytes.append(contentsOf: name(of: link))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func name(of entry: Int32) -> ArraySlice<UInt8> {
        names[Int(nameStarts[Int(entry)])..<Int(nameStarts[Int(entry) + 1])]
    }

    // MARK: Searching

    /// The best `limit` matches for `query` by name, best first: score plus boost, then shorter name, then index
    /// order. Spread over the cores once the index is big enough to be worth it.
    public func search(_ query: String, limit: Int) -> [FileHit] {
        guard limit > 0, !FuzzyMatcher(query: query).isEmpty, !flags.isEmpty else { return [] }
        let total = flags.count
        let chunks = min(max(1, total / 4096), Self.cores)
        var tops = [[Candidate]](repeating: [], count: chunks)

        keys.bytes.withUnsafeBufferPointer { bytes in
            keys.bonus.withUnsafeBufferPointer { bonus in
                keys.starts.withUnsafeBufferPointer { starts in
                    keys.masks.withUnsafeBufferPointer { masks in
                        flags.withUnsafeBufferPointer { flags in
                            boosts.withUnsafeBufferPointer { boosts in
                                tops.withUnsafeMutableBufferPointer { tops in
                                    // Each chunk reads shared, unchanging buffers and writes only its own slot.
                                    nonisolated(unsafe) let bytes = bytes
                                    nonisolated(unsafe) let bonus = bonus
                                    nonisolated(unsafe) let starts = starts
                                    nonisolated(unsafe) let masks = masks
                                    nonisolated(unsafe) let flags = flags
                                    nonisolated(unsafe) let boosts = boosts
                                    nonisolated(unsafe) let tops = tops
                                    let skip = Self.removed | Self.root
                                    DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                                        var matcher = FuzzyMatcher(query: query)
                                        var top = TopMatches(limit: limit)
                                        for index in (chunk * total / chunks)..<((chunk + 1) * total / chunks)
                                        where flags[index] & skip == 0 {
                                            let start = Int(starts[index])
                                            let end = Int(starts[index + 1])
                                            guard
                                                let score = matcher.score(
                                                    text: UnsafeBufferPointer(rebasing: bytes[start..<end]),
                                                    bonus: UnsafeBufferPointer(rebasing: bonus[start..<end]),
                                                    mask: masks[index])
                                            else { continue }
                                            top.insert(
                                                Candidate(
                                                    score: score + boosts[index], length: end - start, index: index))
                                        }
                                        tops[chunk] = top.items
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        var merged = TopMatches(limit: limit)
        for candidate in tops.joined() { merged.insert(candidate) }
        return merged.items.map {
            FileHit(path: path(of: Int32($0.index)), isFolder: flags[$0.index] & Self.folder != 0, score: $0.score)
        }
    }

    /// What the index holds in memory, from its arrays' and tables' capacities: an estimate that ignores allocator
    /// overhead.
    public var memoryBytes: Int {
        func size<T>(_ array: [T]) -> Int { array.capacity * MemoryLayout<T>.stride }
        let childLists = children.values.reduce(0) { $0 + size($1) + 32 }
        return size(names) + size(nameStarts) + size(parents) + size(depths) + size(flags) + size(boosts)
            + keys.memoryBytes + childLists
            + children.capacity * (MemoryLayout<Int32>.stride + MemoryLayout<[Int32]>.stride + 1)
            + lookup.capacity * (MemoryLayout<ChildKey>.stride + MemoryLayout<Int32>.stride + 1)
    }

    /// Reallocates every array at its exact size: after a full scan they can hold up to twice what they need.
    public mutating func trim() {
        func exact<T>(_ array: inout [T]) { array = array.withUnsafeBufferPointer { Array($0) } }
        exact(&names)
        exact(&nameStarts)
        exact(&parents)
        exact(&depths)
        exact(&flags)
        exact(&boosts)
        keys.trim()
    }

    // MARK: Storage

    private mutating func append(name: String, parent: Int32, depth: UInt8, flag: UInt8, searchable: Bool) -> Int32 {
        let entry = Int32(flags.count)
        names.append(contentsOf: name.utf8)
        nameStarts.append(UInt32(names.count))
        parents.append(parent)
        depths.append(depth)
        flags.append(flag)
        boosts.append(0)
        keys.append(searchable ? name : "")
        return entry
    }

    /// Rebuilds the arrays without removed entries once they're more than a quarter of the index.
    private mutating func compactIfNeeded() {
        guard removedCount > 1024, removedCount * 4 > flags.count else { return }
        var compacted = FileIndex()
        compacted.keys.reserveCapacity(keys: count + rootCount, bytes: keys.bytes.count)
        var renumbered = [Int32](repeating: -1, count: flags.count)
        // Parents always come before their children, so one pass in order rebuilds the tree.
        for index in flags.indices where flags[index] & Self.removed == 0 {
            let entry = Int32(index)
            let name = String(decoding: name(of: entry), as: UTF8.self)
            if flags[index] & Self.root != 0 {
                renumbered[index] = compacted.addRoot(name)
            } else if parents[index] >= 0, renumbered[Int(parents[index])] >= 0 {
                let new = compacted.add(
                    name: name, parent: renumbered[Int(parents[index])], isFolder: flags[index] & Self.folder != 0)
                compacted.boosts[Int(new)] = boosts[index]
                renumbered[index] = new
            }
        }
        self = compacted
    }
}

/// A child's slot in `FileIndex.lookup`: its parent and a 64-bit FNV-1a hash of its name.
private struct ChildKey: Hashable {
    let parent: Int32
    let name: UInt64

    init(parent: Int32, name: some Sequence<UInt8>) {
        self.parent = parent
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        self.name = hash
    }
}

struct Candidate {
    let score: Int32
    /// Name length, the first tie-breaker: shorter wins.
    let length: Int
    let index: Int

    /// Better first: higher score, then shorter name, then earlier in the index.
    func isBetter(than other: Candidate) -> Bool {
        if score != other.score { return score > other.score }
        if length != other.length { return length < other.length }
        return index < other.index
    }
}

/// The best `limit` candidates seen so far, kept sorted best first. Inserting a candidate that can't make the list
/// costs one comparison.
struct TopMatches {
    let limit: Int
    private(set) var items: [Candidate] = []

    init(limit: Int) {
        self.limit = limit
        items.reserveCapacity(limit)
    }

    mutating func insert(_ candidate: Candidate) {
        if items.count == limit {
            guard let worst = items.last, candidate.isBetter(than: worst) else { return }
            items.removeLast()
        }
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].isBetter(than: candidate) { low = middle + 1 } else { high = middle }
        }
        items.insert(candidate, at: low)
    }
}

extension FileIndex {
    /// A name's last path component, for paths given as strings.
    static func name(of path: String) -> Substring {
        path.lastIndex(of: "/").map { path[path.index(after: $0)...] } ?? path[...]
    }
}
