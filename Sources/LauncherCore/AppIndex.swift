import Foundation

/// An application bundle found on disk.
public struct AppItem: Sendable, Hashable {
    /// The name Finder shows: localized, without `.app`.
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

/// The in-memory app index: built off the main thread, then searched on every keystroke.
public struct AppIndex: Sendable {
    /// Sorted by name, so ties in a search come out alphabetical.
    public let apps: [AppItem]
    private let names: [SearchKey]
    /// The bundle's file name when it differs from the localized name, so "calcu" finds "Calcolatrice".
    private let fileNames: [SearchKey?]

    public static let empty = AppIndex(apps: [])

    public init(apps: [AppItem]) {
        let apps = apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.apps = apps
        names = apps.map { SearchKey($0.name) }
        fileNames = apps.map { app in
            let fileName = app.url.deletingPathExtension().lastPathComponent
            return fileName == app.name ? nil : SearchKey(fileName)
        }
    }

    /// Indices into `apps` of the best matches for `query`, best first. An empty query matches nothing.
    ///
    /// Ranked by match score, then by shorter name, then alphabetically.
    public func search(_ query: String, limit: Int) -> [Int] {
        var matcher = FuzzyMatcher(query: query)
        guard !matcher.isEmpty else { return [] }

        var hits: [(score: Int32, index: Int)] = []
        for index in apps.indices {
            var best = matcher.score(names[index])
            if let fileName = fileNames[index], let score = matcher.score(fileName), score > best ?? .min {
                best = score
            }
            if let best { hits.append((best, index)) }
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
