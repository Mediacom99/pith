import Foundation
import Synchronization
import TestSupport
import Testing

@testable import LauncherCore

/// Polls `condition` until it holds or `timeout` passes.
private func eventually(within timeout: Duration = .seconds(5), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

struct IgnoreRulesTests {
    private let rules = IgnoreRules(
        [".*", "node_modules", "*.photoslibrary", "build*", "temp?.txt", "~/Library", "/opt/stuff/"], home: "/Users/me")

    @Test(arguments: [
        (".git", "/Users/me/p/.git"),
        ("node_modules", "/Users/me/p/node_modules"),
        ("Photos Library.photoslibrary", "/Users/me/Pictures/Photos Library.photoslibrary"),
        ("build-output", "/Users/me/p/build-output"),
        ("temp1.txt", "/Users/me/temp1.txt"),
        ("Library", "/Users/me/Library"),
        ("Caches", "/Users/me/Library/Caches"),
        ("x", "/opt/stuff/x"),
    ])
    func ignores(name: String, path: String) {
        #expect(rules.ignores(name: name, path: path))
    }

    @Test(arguments: [
        ("notes.md", "/Users/me/notes.md"),
        ("Library", "/Users/me/Projects/Library"),
        ("LibraryX", "/Users/me/LibraryX"),
        ("temp12.txt", "/Users/me/temp12.txt"),
        ("rebuild", "/Users/me/rebuild"),
    ])
    func keeps(name: String, path: String) {
        #expect(!rules.ignores(name: name, path: path))
    }
}

struct FileScannerTests {
    private func scan(_ root: URL, ignore: [String] = [".*", "node_modules"], depth: Int = 6) -> FileIndex {
        var index = FileIndex()
        FileScanner.scan(FileRules(roots: [root.path], ignore: IgnoreRules(ignore), maxDepth: depth), into: &index)
        return index
    }

    @Test func indexesFilesAndFoldersAndSkipsIgnoredOnes() throws {
        let root = try TemporaryDirectory()
        try root.makeFolder("Docs/Deep")
        try root.makeFile("Docs/notes.md")
        try root.makeFile("Docs/Deep/plan.txt")
        try root.makeFile(".secret")
        try root.makeFolder(".git/objects")
        try root.makeFile("node_modules/lib/index.js")

        let index = scan(root.url)
        let base = root.url.path
        #expect(index.isFolder(base + "/Docs") == true)
        #expect(index.isFolder(base + "/Docs/notes.md") == false)
        #expect(index.contains(base + "/Docs/Deep/plan.txt"))
        #expect(!index.contains(base + "/.secret"))
        #expect(!index.contains(base + "/.git"))
        #expect(!index.contains(base + "/node_modules/lib/index.js"))
        #expect(!index.contains(base), "a root isn't an entry of its own")
        #expect(index.count == 4)
    }

    @Test func packagesAreFilesAndNotEntered() throws {
        let root = try TemporaryDirectory()
        try root.makeFile("Tool.app/Contents/Info.plist")
        let index = scan(root.url)
        #expect(index.isFolder(root.url.path + "/Tool.app") == false)
        #expect(!index.contains(root.url.path + "/Tool.app/Contents"))
    }

    @Test func stopsAtTheMaximumDepth() throws {
        let root = try TemporaryDirectory()
        try root.makeFile("1/2/3/deep.txt")
        let index = scan(root.url, depth: 2)
        #expect(index.contains(root.url.path + "/1/2"))
        #expect(!index.contains(root.url.path + "/1/2/3"))
    }

    @Test func doesntFollowSymlinks() throws {
        let root = try TemporaryDirectory()
        try root.makeFile("Real/inside.txt")
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "Link"), withDestinationURL: root.url.appending(path: "Real"))
        let index = scan(root.url)
        #expect(index.isFolder(root.url.path + "/Link") == false)
        #expect(!index.contains(root.url.path + "/Link/inside.txt"))
    }

    /// A folder that was asked for is indexed even inside an ignored one (Dropbox in `~/Library/CloudStorage`) or
    /// when it's hidden (`~/.config`); the rest of the ignored folder stays out.
    @Test func aRootIsIndexedEvenWhereTheRulesWouldSkipIt() throws {
        let home = try TemporaryDirectory()
        let dropbox = home.url.path + "/Library/CloudStorage/Dropbox"
        try home.makeFile("Library/CloudStorage/Dropbox/Acme/report.pdf")
        try home.makeFile("Library/Caches/junk.txt")
        try home.makeFile(".config/pith/config.toml")
        try home.makeFile("notes.md")
        let rules = FileRules(
            roots: [home.url.path, dropbox, home.url.path + "/.config"],
            ignore: IgnoreRules([".*", "~/Library"], home: home.url.path), maxDepth: 6)
        var index = FileIndex()
        FileScanner.scan(rules, into: &index)
        #expect(index.contains(dropbox + "/Acme/report.pdf"))
        #expect(index.contains(home.url.path + "/.config/pith/config.toml"))
        #expect(index.contains(home.url.path + "/notes.md"))
        #expect(!index.contains(home.url.path + "/Library/Caches/junk.txt"))
        #expect(index.count == 5, "each once: Acme, pith and the three files")
        #expect(rules.excludedPaths.isEmpty, "FSEvents still sees ~/Library, which holds a root")
        #expect(!rules.ignore(at: dropbox + "/Acme").ignores(name: "Acme", path: dropbox + "/Acme"))
        #expect(
            rules.ignore(at: home.url.path + "/Library/Caches").ignores(
                name: "Caches", path: home.url.path + "/Library/Caches"))
    }

    /// The protected folders a scan would read, and the rules without them (decision 60).
    @Test func protectedFoldersAreLeftOutUntilAllowed() throws {
        let home = "/Users/acme"
        let rules = FileRules(
            roots: [home, home + "/Documents/dev"],
            ignore: IgnoreRules([".*", "~/Library", "~/Downloads"], home: home),
            maxDepth: 6,
            protected: ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"].map { home + "/" + $0 })
        #expect(rules.protectedFolders == [home + "/Desktop", home + "/Documents"], "ignored ones aren't asked about")
        let deferred = rules.deferring([home + "/Documents"])
        #expect(deferred.roots == [home], "a root in a folder left out waits for it")
        #expect(deferred.ignore(at: home + "/Documents").ignores(name: "Documents", path: home + "/Documents"))
        #expect(deferred.excludedPaths.contains(home + "/Documents"))
        #expect(rules.deferring([]) == rules)
    }

    /// Reading a folder: allowed, refused, or not there (nothing to ask about).
    @Test func canReadAFolder() throws {
        let folder = try TemporaryDirectory()
        try folder.makeFolder("Locked")
        let locked = folder.url.path + "/Locked"
        #expect(FileSearchEngine.canRead(folder.url.path))
        #expect(FileSearchEngine.canRead(folder.url.path + "/Missing"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
        #expect(!FileSearchEngine.canRead(locked))
    }

    @Test func rescansASubtreeAtItsDepth() throws {
        let root = try TemporaryDirectory()
        try root.makeFile("a/b/c/d.txt")
        let rules = FileRules(roots: [root.url.path], ignore: IgnoreRules([]), maxDepth: 3)
        var index = FileIndex()
        FileScanner.scan(rules, into: &index)
        #expect(index.contains(root.url.path + "/a/b/c"))
        #expect(!index.contains(root.url.path + "/a/b/c/d.txt"), "depth 4 is past the limit")

        index.removeDescendants(of: root.url.path + "/a/b")
        #expect(!index.contains(root.url.path + "/a/b/c"))
        FileScanner.scan(folder: root.url.path + "/a/b", rules: rules, into: &index)
        #expect(index.contains(root.url.path + "/a/b/c"))
        #expect(!index.contains(root.url.path + "/a/b/c/d.txt"))
    }
}

struct FileIndexTests {
    /// An index rooted at `root`, with every path's missing folders added along the way.
    private func index(_ paths: [String], root: String = "/f", folders: Set<String> = []) -> FileIndex {
        var index = FileIndex()
        index.addRoot(root)
        for path in paths {
            var folder = root
            for component in path.dropFirst(root.count + 1).split(separator: "/").dropLast() {
                folder += "/\(component)"
                index.insert(folder, isFolder: true)
            }
            index.insert(path, isFolder: folders.contains(path))
        }
        return index
    }

    @Test func rebuildsPathsAndFindsEntries() {
        let files = index(["/f/a/ü b/c.txt", "/f/d.txt"])
        let entry = files.entry(at: "/f/a/ü b/c.txt")
        #expect(entry.map(files.path(of:)) == "/f/a/ü b/c.txt")
        #expect(files.isFolder("/f/a/ü b") == true)
        #expect(files.count == 4)
        #expect(!files.contains("/f"), "a root isn't an entry")
        #expect(files.entry(at: "/g/x") == nil)
    }

    @Test func insertingOutsideTheIndexFails() {
        var files = index(["/f/a.txt"])
        let outside = files.insert("/g/b.txt", isFolder: false)
        let orphan = files.insert("/f/missing/b.txt", isFolder: false)
        let underFile = files.insert("/f/a.txt/b", isFolder: false)
        let inside = files.insert("/f/b.txt", isFolder: false)
        #expect(!outside, "not under a root")
        #expect(!orphan, "parent not indexed")
        #expect(!underFile, "parent is a file")
        #expect(inside)
    }

    @Test func matchesNamesNotFolders() {
        let files = index(
            ["/u/Projects/gizmo/README.md", "/u/Projects/readme-old.txt", "/u/gizmo.txt"], root: "/u")
        #expect(
            files.search("readme", limit: 10).map(\.path) == [
                "/u/Projects/gizmo/README.md", "/u/Projects/readme-old.txt",
            ])
        #expect(
            files.search("gizmo", limit: 10).map(\.path) == ["/u/Projects/gizmo", "/u/gizmo.txt"],
            "the folder named gizmo matches; README.md inside it doesn't")
    }

    @Test func matchesSeveralWordsInAnyOrder() {
        let files = index([
            "/f/Downloads/Quarterly_Budget_Review_Final.pdf", "/f/Downloads/Quarterly_Sales.pdf",
        ])
        let budget = ["/f/Downloads/Quarterly_Budget_Review_Final.pdf"]
        #expect(files.search("quarterly review", limit: 10).map(\.path) == budget)
        #expect(files.search("review quarterly", limit: 10).map(\.path) == budget)
        #expect(files.search("  quarterly   review ", limit: 10).map(\.path) == budget)
        #expect(files.search("quarterly zebra", limit: 10).isEmpty, "every word must match")
    }

    @Test func earlierWordsCanMatchFoldersAbove() {
        let files = index([
            "/f/Projects/Acme/customers/scripts/deploy.sh", "/f/Projects/Other/scripts/deploy.sh",
            "/f/Projects/Acme/readme.md",
        ])
        #expect(
            files.search("acme deploy", limit: 10).map(\.path) == ["/f/Projects/Acme/customers/scripts/deploy.sh"]
        )
        #expect(
            files.search("acme/deploy", limit: 10).map(\.path) == ["/f/Projects/Acme/customers/scripts/deploy.sh"]
        )
        #expect(files.search("~/Projects/Acme/deploy", limit: 10).count == 1)
        #expect(
            Set(files.search("scripts deploy", limit: 10).map(\.path)) == [
                "/f/Projects/Acme/customers/scripts/deploy.sh", "/f/Projects/Other/scripts/deploy.sh",
            ])
        #expect(
            files.search("acme", limit: 10).map(\.path) == ["/f/Projects/Acme"], "one word: names only, no flood")
        #expect(
            files.search("deploy acme", limit: 10).isEmpty,
            "the last word names the item, and nothing named acme sits under a deploy folder")
    }

    @Test func aMatchInTheNameBeatsOneInThePath() {
        let files = index(["/f/notes/plan.txt", "/f/misc/notes-plan.txt"])
        #expect(files.search("notes plan", limit: 10).first?.path == "/f/misc/notes-plan.txt")
    }

    @Test func ranksAndLimits() {
        let files = index((0..<100).map { "/f/report \($0).pdf" } + ["/f/report.pdf"])
        let hits = files.search("report", limit: 5)
        #expect(hits.count == 5)
        #expect(hits.first?.path == "/f/report.pdf", "shortest name first among equal scores")
        #expect(zip(hits, hits.dropFirst()).allSatisfy { $0.score >= $1.score })
    }

    @Test func boostsReorder() {
        var files = index(["/f/notes.md", "/f/notes-archive.md"])
        files.setBoosts(["/f/notes-archive.md": 40])
        #expect(files.search("notes", limit: 2).first?.path == "/f/notes-archive.md")
    }

    @Test func removingAFolderRemovesWhatsInside() {
        var files = index(["/f/a/x.txt", "/f/a/b/y.txt", "/f/ab.txt"])
        #expect(files.count == 5)
        files.remove("/f/a")
        #expect(files.count == 1)
        #expect(files.contains("/f/ab.txt"), "a sibling sharing the prefix stays")
        #expect(files.search("x.txt", limit: 10).isEmpty)
        let orphan = files.insert("/f/a/x.txt", isFolder: false)
        #expect(!orphan, "its folder is gone too")
        files.insert("/f/a", isFolder: true)
        files.insert("/f/a/x.txt", isFolder: false)
        #expect(files.search("x.txt", limit: 10).map(\.path) == ["/f/a/x.txt"])
    }

    @Test func compactsAfterManyRemovals() {
        var files = index((0..<4000).map { "/f/file\($0).txt" })
        for number in 0..<3000 { files.remove("/f/file\(number).txt") }
        #expect(files.count == 1000)
        #expect(files.search("file3999", limit: 1).first?.path == "/f/file3999.txt")
        #expect(files.search("file12", limit: 10).isEmpty == false)
        #expect(!files.contains("/f/file12.txt"))
    }

    @Test func searchesInParallelLikeSequentially() {
        let paths = (0..<50_000).map { "/f/\($0 % 7 == 0 ? "invoice" : "photo") \($0).pdf" }
        let files = index(paths)
        let hits = files.search("invoice 7", limit: 20)
        #expect(hits.count == 20)
        #expect(hits.allSatisfy { FileIndex.name(of: $0.path).hasPrefix("invoice") })
    }
}

struct FileSearchEngineTests {
    @Test func rebuildsAndSearches() async throws {
        let root = try TemporaryDirectory()
        try root.makeFile("Notes/todo.md")
        let engine = FileSearchEngine()
        await engine.rebuild(FileRules(roots: [root.url.path], ignore: IgnoreRules([]), maxDepth: 6))
        #expect(await engine.count == 2)
        let hits = await engine.search("todo", limit: 5, generation: 1)
        #expect(hits?.map(\.path) == [root.url.path + "/Notes/todo.md"])
    }

    /// A config change during a long first scan: the newer, smaller scan wins even though the old one finishes last.
    @Test func theNewestRebuildWins() async throws {
        let big = try TemporaryDirectory()
        for folder in 0..<40 {
            for file in 0..<50 { try big.makeFile("Folder \(folder)/old-file-\(file).txt") }
        }
        let small = try TemporaryDirectory()
        try small.makeFile("new-file.txt")
        let engine = FileSearchEngine()
        let first = Task {
            await engine.rebuild(FileRules(roots: [big.url.path], ignore: IgnoreRules([]), maxDepth: 6))
        }
        while engine.rebuildsAsked < 1 { await Task.yield() }
        await engine.rebuild(FileRules(roots: [small.url.path], ignore: IgnoreRules([]), maxDepth: 6))
        await first.value
        #expect(await engine.count == 1)
        #expect(await engine.search("old-file", limit: 5, generation: 1) == [])
    }

    /// A protected folder whose prompt is up is left out, the rest is searchable at once, and the folder joins as
    /// soon as it's allowed (decision 60).
    @Test func aFolderWaitingOnItsPromptJoinsOnceAllowed() async throws {
        let home = try TemporaryDirectory()
        try home.makeFile("Documents/Acme/report.pdf")
        try home.makeFile("notes.md")
        let documents = home.url.path + "/Documents"
        let prompt = DispatchSemaphore(value: 0)
        let engine = FileSearchEngine(canRead: { folder in
            if folder == documents { prompt.wait() }
            return true
        })
        await engine.rebuild(
            FileRules(roots: [home.url.path], ignore: IgnoreRules([]), maxDepth: 6, protected: [documents]))
        #expect(await engine.search("notes", limit: 5, generation: 1)?.count == 1, "searchable at once")
        #expect(await engine.search("report", limit: 5, generation: 2) == [])

        prompt.signal()
        #expect(await eventually { await engine.search("report", limit: 5, generation: 3)?.count == 1 })
    }

    /// A refused folder is read again as the panel opens, and joins once allowed in System Settings.
    @Test func aRefusedFolderJoinsOnceAllowedLater() async throws {
        let home = try TemporaryDirectory()
        try home.makeFile("Downloads/invoice.pdf")
        let downloads = home.url.path + "/Downloads"
        let allowed = Mutex(false)
        let engine = FileSearchEngine(canRead: { _ in allowed.withLock { $0 } })
        await engine.rebuild(
            FileRules(roots: [home.url.path], ignore: IgnoreRules([]), maxDepth: 6, protected: [downloads]))
        #expect(await engine.search("invoice", limit: 5, generation: 1) == [])
        engine.recheckRefused()
        #expect(await engine.search("invoice", limit: 5, generation: 2) == [], "still refused")

        allowed.withLock { $0 = true }
        engine.recheckRefused()
        #expect(await eventually { await engine.search("invoice", limit: 5, generation: 3)?.count == 1 })
    }

    @Test func staleSearchesSkip() async {
        let engine = FileSearchEngine()
        async let old = engine.search("a", limit: 5, generation: 1)
        _ = await engine.search("ab", limit: 5, generation: 2)
        let stale = await old
        // The first may have run before the second was asked for; if it hadn't, it skipped.
        #expect(stale == nil || stale == [])
        #expect(await engine.search("abc", limit: 5, generation: 3) == [])
    }
}
