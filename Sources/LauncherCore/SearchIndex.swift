import Foundation

/// The in-memory index of apps and commands: built off the main thread, then searched on every keystroke.
public struct SearchIndex: Sendable {
    /// Sorted by name, so ties in a search come out alphabetical.
    public let items: [Item]
    private let names: [SearchKey]
    /// An app's file name when it differs from its localized name, so "calcu" finds "Calcolatrice".
    private let fileNames: [SearchKey?]
    private let positions: [String: Int]

    public static let empty = SearchIndex(items: [])

    public init(items: [Item]) {
        let items = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.items = items
        names = items.map { SearchKey($0.name) }
        fileNames = items.map { item in
            guard let fileName = item.url?.deletingPathExtension().lastPathComponent, fileName != item.name else {
                return nil
            }
            return SearchKey(fileName)
        }
        positions = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Where the item with this `Item.id` sits in `items`.
    public func position(of id: String) -> Int? {
        positions[id]
    }

    /// Indices into `items` of the best matches for `query`, best first. An empty query matches nothing.
    ///
    /// Ranked by match score plus `boosts[index]` (the learned ranking, see `History.boosts`; pass none to rank by
    /// match alone), then by shorter name, then alphabetically.
    public func search(_ query: String, limit: Int, boosts: [Int32] = []) -> [Int] {
        var matcher = FuzzyMatcher(query: query)
        guard !matcher.isEmpty else { return [] }
        let boosted = boosts.count == items.count

        var hits: [(score: Int32, index: Int)] = []
        for index in items.indices {
            var best = matcher.score(names[index])
            if let fileName = fileNames[index], let score = matcher.score(fileName), score > best ?? .min {
                best = score
            }
            if let best { hits.append((boosted ? best + boosts[index] : best, index)) }
        }
        hits.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let lengthA = names[a.index].bytes.count
            let lengthB = names[b.index].bytes.count
            return lengthA != lengthB ? lengthA < lengthB : a.index < b.index
        }
        return hits.prefix(limit).map(\.index)
    }
}
