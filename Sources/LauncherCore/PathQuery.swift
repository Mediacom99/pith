import Foundation

/// A query that's a path, as in a terminal (decision 81): it starts with `/` or `~/`. What's typed up to the last
/// slash is the folder to list, and what follows narrows it.
public struct PathQuery: Sendable, Equatable {
    /// The folder as typed, `~` kept, with its last slash: "~/Documents/". Tab completes after it.
    public let typedFolder: String
    /// The folder on disk, `~` expanded and doubled slashes made one, with its last slash: "/Users/me/Documents/".
    public let folder: String
    /// What's typed after the last slash: the names that start with it are listed.
    public let prefix: String

    public init?(_ query: String, home: String = NSHomeDirectory()) {
        guard query.hasPrefix("/") || query.hasPrefix("~/"), let slash = query.lastIndex(of: "/") else { return nil }
        typedFolder = String(query[...slash])
        prefix = String(query[query.index(after: slash)...])
        var folder = typedFolder.hasPrefix("~/") ? home + "/" + typedFolder.dropFirst(2) : typedFolder
        while let doubled = folder.range(of: "//") { folder.replaceSubrange(doubled, with: "/") }
        self.folder = folder
    }

    /// The query with `name` in place of the prefix, as Tab fills it in: a folder ends in `/`, so its contents show.
    public func completed(with name: String, isFolder: Bool) -> String {
        typedFolder + name + (isFolder ? "/" : "")
    }
}

/// A folder's contents, read once and narrowed as the name after the last slash is typed (decision 81).
public struct FolderListing: Sendable {
    public struct Entry: Sendable, Equatable {
        public let name: String
        /// A folder, or a link to one; a package (an app, a bundle) is a file, as in the index.
        public let isFolder: Bool
        /// The name lowercased and without accents, for the prefix to match.
        let folded: String
    }

    /// As `PathQuery.folder` gives it, with its last slash.
    public let folder: String
    /// Sorted as Finder sorts.
    public let entries: [Entry]

    /// Reads `folder`. Blocks on the disk (and on macOS's prompt for a protected folder): call it on a worker. A folder
    /// that's missing or can't be read has no entries.
    public init(reading folder: String) {
        self.folder = folder
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: URL(filePath: folder, directoryHint: .isDirectory), includingPropertiesForKeys: keys)) ?? []
        entries = urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            var isFolder = values?.isDirectory == true
            if values?.isSymbolicLink == true {
                var isDirectory: ObjCBool = false
                isFolder =
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
            if isFolder, values?.isPackage == true || FileScanner.isPackage(url.path) { isFolder = false }
            let name = url.lastPathComponent
            return Entry(name: name, isFolder: isFolder, folded: Self.fold(name))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A listing already known, in the order given: the snapshots' made-up folders.
    public init(folder: String, entries: [(name: String, isFolder: Bool)]) {
        self.folder = folder
        self.entries = entries.map { Entry(name: $0.name, isFolder: $0.isFolder, folded: Self.fold($0.name)) }
    }

    /// The first `limit` entries whose names start with `prefix`, ignoring case and accents. Hidden names (a leading
    /// dot) only once the prefix starts with one, as in a terminal.
    public func matching(_ prefix: String, limit: Int) -> [Entry] {
        let folded = Self.fold(prefix)
        let showsHidden = prefix.hasPrefix(".")
        var found: [Entry] = []
        for entry in entries where entry.folded.hasPrefix(folded) && (showsHidden || !entry.name.hasPrefix(".")) {
            found.append(entry)
            if found.count == limit { break }
        }
        return found
    }

    /// Where `entry` is on disk.
    public func path(of entry: Entry) -> String {
        folder + entry.name
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
