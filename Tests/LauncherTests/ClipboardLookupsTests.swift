import Foundation
import LauncherCore
import Synchronization
import Testing

@testable import Launcher

/// What the clipboard's tile looks up on a worker: a copied file's facts, and the app a link opens in.
@MainActor
struct ClipboardLookupsTests {
    /// A clip's files are read together once per opening of the clipboard, and the tile is told only when the answer
    /// changed: a copy of thousands of files is one job and one redraw, not one per file.
    @Test func fileFactsAreReadOncePerOpeningAndReportOnlyChanges() async {
        let facts = FileFacts()
        let reads = Atomic<Int>(0)
        let size = Atomic<Int>(1_000)
        facts.read = { _ in
            reads.add(1, ordering: .relaxed)
            return (true, size.load(ordering: .relaxed))
        }
        var changes = 0
        facts.onChange = { changes += 1 }
        let clip = files((0..<2_000).map { "/Users/me/Documents/Acme/scan-\($0).pdf" })

        #expect(facts.summary(of: clip) == nil, "unknown until the first read lands")
        #expect(await eventuallyTrue { facts.summary(of: clip)?.bytes == 2_000_000 })
        #expect(reads.load(ordering: .relaxed) == 2_000, "fresh: asking again doesn't read again")
        #expect(changes == 1, "one redraw for the whole list")

        facts.markStale()
        #expect(facts.summary(of: clip)?.bytes == 2_000_000, "the last answer shows while it's read again")
        #expect(await eventuallyTrue { reads.load(ordering: .relaxed) == 4_000 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changes == 1, "the same answer redraws nothing")

        size.store(2_000, ordering: .relaxed)
        facts.markStale()
        _ = facts.summary(of: clip)
        #expect(await eventuallyTrue { facts.summary(of: clip)?.bytes == 4_000_000 })
        #expect(changes == 2)
    }

    /// A folder has no size of its own to show, a list cut in memory has no total, and files that are gone add none.
    @Test func aSizeIsShownOnlyWhenItsWhole() async {
        let facts = FileFacts()
        facts.read = { path in path.hasSuffix("/") ? (true, nil) : path.contains("gone") ? (false, nil) : (true, 10) }
        let folder = files(["/Users/me/Acme/", "/Users/me/notes.md"], id: 1)
        let gone = files(["/Users/me/gone.md", "/Users/me/notes.md"], id: 2)
        var cut = files(["/Users/me/notes.md", "/Users/me/to-do.md", "/Users/me/rep"], id: 3)
        cut.textBytes += 20

        #expect(await eventuallyTrue { facts.summary(of: folder) == .init(firstExists: true, bytes: nil) })
        #expect(await eventuallyTrue { facts.summary(of: gone) == .init(firstExists: false, bytes: 10) })
        #expect(await eventuallyTrue { facts.summary(of: cut) == .init(firstExists: true, bytes: nil) })
        #expect(ClipText.folders(of: folder) == "/Users/me", "a folder's own slash isn't its parent")
        #expect(IconSource(URL(filePath: ClipText.firstPath(of: folder))).key == "folder", "a folder's icon")
        #expect(ClipText.folders(of: files(["/Users/me/a.md", "/Users/me/Acme/b.md"])) == "2 folders")
        #expect(ClipText.folders(of: cut) == "/Users/me", "the cut path isn't counted")
    }

    private func files(_ paths: [String], id: Int64 = 0) -> Clip {
        let text = paths.joined(separator: "\n")
        return Clip(
            id: id, kind: .files, copied: .now, source: nil, pinned: false, size: 0, text: text,
            lines: paths.count)
    }

    /// `[open_links]`'s app for a scheme, in any case; a change to the setting forgets what was looked up.
    @Test func linkAppsUseTheConfiguredAppAndForgetItWhenItChanges() async {
        let links = LinkApps()
        let textEdit = URL(filePath: "/System/Applications/TextEdit.app")
        links.configured = ["https": textEdit]

        #expect(links.app(for: "not a link") == nil)
        let first = links.app(for: "HTTPS://acme.example")
        #expect(first?.url == textEdit && first?.name == nil, "the configured app at once, its name on a worker")
        #expect(await eventuallyTrue { links.app(for: "https://acme.example")?.name == "TextEdit" })
        #expect(links.app(for: "mailto:jane@acme.example") == nil, "a default app is looked up first")

        let safari = URL(filePath: "/Applications/Safari.app")
        links.configured = ["https": safari]
        #expect(links.app(for: "https://acme.example")?.url == safari, "the new setting at once")
        #expect(await eventuallyTrue { links.app(for: "https://acme.example")?.name == "Safari" })

        // The clipboard opening again looks it up again: the answer shows meanwhile, and the same one redraws nothing.
        var changes = 0
        links.onChange = { changes += 1 }
        links.markStale()
        #expect(links.app(for: "https://acme.example")?.name == "Safari")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(changes == 0)
    }
}
