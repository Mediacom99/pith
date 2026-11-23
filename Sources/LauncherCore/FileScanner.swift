import Darwin
import Foundation
import UniformTypeIdentifiers

/// What to index: folders, what to skip in them, and how deep to go (FEATURES.md §4.2, decision 22).
///
/// A root is never skipped, since it was asked for, and inside it the rules that would skip it don't apply: a folder
/// in `~/Library/CloudStorage` (Dropbox, Google Drive) is indexed although `~/Library` is ignored, and so is
/// `~/.config` although hidden files are.
public struct FileRules: Sendable, Equatable {
    /// Absolute paths.
    public let roots: [String]
    public let ignore: IgnoreRules
    /// How many folders below a root are indexed: 1 means only a root's direct contents.
    public let maxDepth: Int
    /// Folders macOS asks about before an app reads them (Desktop, Documents, Downloads, iCloud Drive): the index
    /// leaves each out until it's allowed (decision 60).
    public let protected: [String]
    /// `ignore` inside each root, in `roots`' order: without the path rules that hold the root.
    let ignoreInRoots: [IgnoreRules]

    public init(roots: [String], ignore: IgnoreRules, maxDepth: Int, protected: [String] = []) {
        self.roots = roots
        self.ignore = ignore
        self.maxDepth = maxDepth
        self.protected = protected
        ignoreInRoots = roots.map { ignore.inside($0) }
    }

    /// The protected folders a scan would read: in a root and not ignored there, or holding a root.
    var protectedFolders: [String] {
        protected.filter { folder in
            roots.contains { root in
                IgnoreRules.holds(folder, root)
                    || IgnoreRules.holds(root, folder)
                        && !ignore(at: folder).ignores(name: String(FileIndex.name(of: folder)), path: folder)
            }
        }
    }

    /// These rules without `folders`: a root in one is left out, and inside the other roots they're skipped.
    func deferring(_ folders: Set<String>) -> FileRules {
        guard !folders.isEmpty else { return self }
        let roots = roots.filter { root in !folders.contains { IgnoreRules.holds($0, root) } }
        return FileRules(
            roots: roots, ignore: ignore.adding(folders.sorted()), maxDepth: maxDepth, protected: protected)
    }

    /// The rules for `path`: those of the innermost root it's in.
    func ignore(at path: String) -> IgnoreRules {
        var best: (rules: IgnoreRules, length: Int)?
        for (root, rules) in zip(roots, ignoreInRoots)
        where (path == root || path.hasPrefix(root + "/")) && root.count > best?.length ?? -1 {
            best = (rules, root.count)
        }
        return best?.rules ?? ignore
    }

    /// The ignored paths FSEvents can leave out: those that hold no root.
    var excludedPaths: [String] {
        ignore.paths.filter { path in !roots.contains { IgnoreRules.holds(path, $0) } }
    }
}

/// Ignore patterns. A pattern starting with `~/` or `/` skips that exact path and everything under it. Any other
/// pattern matches a file or folder name anywhere: `node_modules`, `.*` (hidden), `*.photoslibrary`, or any `fnmatch`
/// glob.
public struct IgnoreRules: Sendable, Equatable {
    private enum Pattern: Sendable, Equatable {
        case prefix(String)
        case suffix(String)
        case glob(String)
    }

    private let names: Set<String>
    private let patterns: [Pattern]
    /// Absolute, without a trailing slash.
    public private(set) var paths: [String]
    private var pathBytes: [[CChar]]

    public init(_ patterns: [String], home: String = NSHomeDirectory()) {
        var names = Set<String>()
        var compiled: [Pattern] = []
        var paths: [String] = []
        for pattern in patterns where !pattern.isEmpty {
            if pattern == "~" || pattern.hasPrefix("~/") || pattern.hasPrefix("/") {
                var path = pattern.hasPrefix("~") ? home + pattern.dropFirst() : pattern
                while path.count > 1, path.hasSuffix("/") { path.removeLast() }
                paths.append(path)
                continue
            }
            let wildcards = pattern.filter { "*?[".contains($0) }
            if wildcards.isEmpty {
                names.insert(pattern)
            } else if wildcards == "*", pattern.hasPrefix("*") {
                compiled.append(.suffix(String(pattern.dropFirst())))
            } else if wildcards == "*", pattern.hasSuffix("*") {
                compiled.append(.prefix(String(pattern.dropLast())))
            } else {
                compiled.append(.glob(pattern))
            }
        }
        self.names = names
        self.patterns = compiled
        self.paths = paths
        self.pathBytes = paths.map { Array($0.utf8CString.dropLast()) }
    }

    public func ignores(name: String, path: String) -> Bool {
        ignores(name: name) || paths.contains { Self.holds($0, path) }
    }

    /// The rules inside `root`, a folder that was asked for: without the path rules that hold it.
    func inside(_ root: String) -> IgnoreRules {
        var rules = self
        rules.paths = paths.filter { !Self.holds($0, root) }
        rules.pathBytes = rules.paths.map { Array($0.utf8CString.dropLast()) }
        return rules
    }

    /// These rules, also skipping `paths` and everything under them.
    func adding(_ paths: [String]) -> IgnoreRules {
        var rules = self
        rules.paths += paths
        rules.pathBytes = rules.paths.map { Array($0.utf8CString.dropLast()) }
        return rules
    }

    /// Whether `folder` is `path` or one of the folders it's in.
    static func holds(_ folder: String, _ path: String) -> Bool {
        path == folder || path.hasPrefix(folder + "/")
    }

    /// The same, with the path as a C string, as `fts` gives it.
    func ignores(name: String, path: UnsafePointer<CChar>, length: Int) -> Bool {
        if ignores(name: name) { return true }
        for rule in pathBytes where length >= rule.count && memcmp(path, rule, rule.count) == 0 {
            if length == rule.count || path[rule.count] == CChar(UInt8(ascii: "/")) { return true }
        }
        return false
    }

    private func ignores(name: String) -> Bool {
        if names.contains(name) { return true }
        for pattern in patterns {
            switch pattern {
            case .prefix(let prefix): if name.hasPrefix(prefix) { return true }
            case .suffix(let suffix): if name.hasSuffix(suffix) { return true }
            case .glob(let glob): if fnmatch(glob, name, 0) == 0 { return true }
            }
        }
        return false
    }
}

/// Walks folders with `fts` and fills a `FileIndex`. Bundles and other packages count as files, symlinks aren't
/// followed, and the walk never crosses into another volume (so network mounts and disk images are skipped). Names
/// come straight from `fts`, and no full path strings are built.
public enum FileScanner {
    /// Indexes everything under `rules.roots`.
    public static func scan(_ rules: FileRules, into index: inout FileIndex) {
        var packages = PackageCache()
        for (root, ignore) in zip(rules.roots, rules.ignoreInRoots) {
            walk(root, under: index.addRoot(root), rules: rules, ignore: ignore, packages: &packages, into: &index)
        }
    }

    /// Indexes everything under `folder`, an indexed folder whose contents aren't: for folders the live updates
    /// find new, or need to rescan.
    public static func scan(folder: String, rules: FileRules, into index: inout FileIndex) {
        guard let entry = index.entry(at: folder) else { return }
        var packages = PackageCache()
        walk(folder, under: entry, rules: rules, ignore: rules.ignore(at: folder), packages: &packages, into: &index)
    }

    /// Whether a directory with this name is a package (an app, a bundle, a Photos library…), which the index treats
    /// as a file.
    public static func isPackage(_ path: String) -> Bool {
        var packages = PackageCache()
        return packages.isPackage(name: String(FileIndex.name(of: path)))
    }

    private static func walk(
        _ start: String, under startEntry: Int32, rules: FileRules, ignore: IgnoreRules, packages: inout PackageCache,
        into index: inout FileIndex
    ) {
        let startDepth = index.depth(of: startEntry)
        guard startDepth < rules.maxDepth, let pointer = strdup(start) else { return }
        defer { free(pointer) }
        var arguments: [UnsafeMutablePointer<CChar>?] = [pointer, nil]
        guard let fts = fts_open(&arguments, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV | FTS_NOSTAT, nil) else { return }
        defer { fts_close(fts) }

        while let entry = fts_read(fts) {
            let level = Int(entry.pointee.fts_level)
            // Each folder's index entry rides along in fts_number, for its children to find their parent.
            guard level > 0 else {
                entry.pointee.fts_number = Int(startEntry)
                continue
            }
            let info = Int32(entry.pointee.fts_info)
            guard info != FTS_DP, info != FTS_DNR, info != FTS_ERR, info != FTS_DC, info != FTS_NS else { continue }

            let path = entry.pointee.fts_path!
            let pathLength = Int(entry.pointee.fts_pathlen)
            let name = String(cString: path + (pathLength - Int(entry.pointee.fts_namelen)))
            let isDirectory = info == FTS_D
            if ignore.ignores(name: name, path: path, length: pathLength) {
                if isDirectory { fts_set(fts, entry, FTS_SKIP) }
                continue
            }
            let parent = Int32(entry.pointee.fts_parent.pointee.fts_number)
            if isDirectory, packages.isPackage(name: name) {
                index.add(name: name, parent: parent, isFolder: false)
                fts_set(fts, entry, FTS_SKIP)
                continue
            }
            let added = index.add(name: name, parent: parent, isFolder: isDirectory)
            if isDirectory {
                entry.pointee.fts_number = Int(added)
                if startDepth + level >= rules.maxDepth { fts_set(fts, entry, FTS_SKIP) }
            }
        }
    }
}

/// Which folder extensions are packages, asked of the type system once per extension.
private struct PackageCache {
    private var known: [Substring: Bool] = [:]

    mutating func isPackage(name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        let ext = name[name.index(after: dot)...]
        if let answer = known[ext] { return answer }
        let answer = UTType(filenameExtension: String(ext), conformingTo: .directory)?.conforms(to: .package) ?? false
        known[ext] = answer
        return answer
    }
}
