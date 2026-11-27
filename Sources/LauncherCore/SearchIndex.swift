import Foundation

/// The in-memory index of apps and commands: built off the main thread, then searched on every keystroke.
public struct SearchIndex: Sendable {
    /// Sorted by name, so ties in a search come out alphabetical.
    public let items: [Item]
    private let names: [SearchKey]
    /// An app's file name when it differs from its localized name, so "calcu" finds "Calcolatrice".
    private let fileNames: [SearchKey?]
    private let positions: [String: Int]
    /// A command's aliases (`Command.aliases`, or `setAliases`) → its position: a query that is one comes first.
    private var aliases: [String: Int]
    /// Above any match and boost, so an alias's item leads the merged list too.
    static let aliasScore = Int32.max / 4

    public static let empty = SearchIndex(items: [])

    public init(items: [Item]) {
        let items = items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.items = items
        names = items.map { SearchKey($0.name) }
        fileNames = items.map { item in
            guard item.isApp, let fileName = item.url?.deletingPathExtension().lastPathComponent, fileName != item.name
            else {
                return nil
            }
            return SearchKey(fileName)
        }
        positions = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var aliases: [String: Int] = [:]
        for (position, item) in items.enumerated() {
            guard case .command(let command) = item.kind else { continue }
            for alias in command.aliases { aliases[alias] = position }
        }
        self.aliases = aliases
    }

    /// Replaces `command`'s aliases: `[launcher] clipboard_alias` (decision 55).
    public mutating func setAliases(_ names: [String], for command: Command) {
        guard let position = positions[Item(command: command).id] else { return }
        aliases = aliases.filter { $0.value != position }
        for name in names where !name.isEmpty { aliases[name.lowercased()] = position }
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
        scoredSearch(query, limit: limit, boosts: boosts).map(\.index)
    }

    /// The same, with each match's score (boost included), for merging with file results.
    /// Every word of the query (`QueryTerms`) must match the name or file name; the scores add up. A query that asks
    /// for an extension (`*.pdf`) is for files only.
    public func scoredSearch(_ query: String, limit: Int, boosts: [Int32] = []) -> [(index: Int, score: Int32)] {
        let terms = QueryTerms(query)
        var matchers = terms.matchers()
        guard !matchers.isEmpty, terms.extensions.isEmpty else { return [] }
        let boosted = boosts.count == items.count

        var hits: [(index: Int, score: Int32)] = []
        items: for index in items.indices {
            var total: Int32 = 0
            for word in matchers.indices {
                var best = matchers[word].score(names[index])
                if let fileName = fileNames[index], let score = matchers[word].score(fileName), score > best ?? .min {
                    best = score
                }
                guard let best else { continue items }
                total += best
            }
            hits.append((index, boosted ? total + boosts[index] : total))
        }
        // A query that is a command's alias puts that command first.
        if let position = aliases[query.trimmingCharacters(in: .whitespaces).lowercased()] {
            hits.removeAll { $0.index == position }
            hits.append((position, Self.aliasScore))
        }
        hits.sort { a, b in
            if a.score != b.score { return a.score > b.score }
            let lengthA = names[a.index].bytes.count
            let lengthB = names[b.index].bytes.count
            return lengthA != lengthB ? lengthA < lengthB : a.index < b.index
        }
        return Array(hits.prefix(limit))
    }
}
