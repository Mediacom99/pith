import Foundation

/// What was opened from the launcher, and when. It feeds the `recent` empty state and the ranking boost
/// (decisions 11–12).
public struct History: Sendable, Codable, Equatable {
    struct Entry: Sendable, Codable, Equatable {
        var count: Int
        /// The latest opens, oldest first, in seconds since 1970. At most `History.samples`.
        var opens: [Double]
    }

    /// How many open times are kept per item to estimate how recent its use is.
    static let samples = 10
    /// How many items are remembered. Past that, the least used one is forgotten.
    static let capacity = 200

    private var entries: [String: Entry] = [:]

    public init() {}

    public var isEmpty: Bool { entries.isEmpty }

    public mutating func record(_ id: String, at date: Date = .now) {
        var entry = entries[id] ?? Entry(count: 0, opens: [])
        entry.count += 1
        entry.opens.append(date.timeIntervalSince1970)
        if entry.opens.count > Self.samples { entry.opens.removeFirst(entry.opens.count - Self.samples) }
        entries[id] = entry
        if entries.count > Self.capacity,
            let leastUsed = entries.keys.min(by: { frecency(of: $0, now: date) < frecency(of: $1, now: date) })
        {
            entries[leastUsed] = nil
        }
    }

    /// Every remembered item id.
    public var ids: some Collection<String> { entries.keys }

    public mutating func remove(_ id: String) {
        entries[id] = nil
    }

    /// Forgets files and folders that were deleted: each path, and for folders everything under it.
    public mutating func forget(paths: [String]) {
        guard !paths.isEmpty else { return }
        for id in Array(entries.keys) {
            guard let path = Item(fileID: id)?.url?.path else { continue }
            if paths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { entries[id] = nil }
        }
    }

    /// The ranking boost of each file and folder in the history, by path, for the file index.
    public func fileBoosts(now: Date = .now) -> [String: Int32] {
        var boosts: [String: Int32] = [:]
        for id in entries.keys {
            guard let item = Item(fileID: id), let path = item.url?.path else { continue }
            boosts[path] = Self.boost(frecency: frecency(of: id, now: now))
        }
        return boosts
    }

    /// Item ids, most recently opened first.
    public func recent(limit: Int) -> [String] {
        entries.sorted { ($0.value.opens.last ?? 0) > ($1.value.opens.last ?? 0) }.prefix(limit).map(\.key)
    }

    /// Firefox-style frecency: the open count, weighted by how recent the latest opens are.
    public func frecency(of id: String, now: Date = .now) -> Double {
        guard let entry = entries[id], !entry.opens.isEmpty else { return 0 }
        let reference = now.timeIntervalSince1970
        let points = entry.opens.reduce(0) { $0 + Self.weight(daysAgo: (reference - $1) / 86_400) }
        return Double(entry.count) * points / Double(entry.opens.count)
    }

    /// The ranking boost for every item of `index`, aligned with `index.items`.
    public func boosts(for index: SearchIndex, now: Date = .now) -> [Int32] {
        var boosts = [Int32](repeating: 0, count: index.items.count)
        for id in entries.keys {
            if let position = index.position(of: id) {
                boosts[position] = Self.boost(frecency: frecency(of: id, now: now))
            }
        }
        return boosts
    }

    /// Grows with the log of frecency and caps at 48, the worth of about three well-placed matched characters. Habits
    /// reorder close matches without burying a clearly better one.
    static func boost(frecency: Double) -> Int32 {
        Int32(min(48, (12 * log2(1 + frecency / 100)).rounded()))
    }

    private static func weight(daysAgo days: Double) -> Double {
        switch days {
        case ..<4: 100
        case ..<14: 70
        case ..<31: 50
        case ..<90: 30
        default: 10
        }
    }
}
