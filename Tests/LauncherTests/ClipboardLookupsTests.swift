import Foundation
import Synchronization
import Testing

@testable import Launcher

/// What the clipboard's tile looks up on a worker: a copied file's facts, and the app a link opens in.
@MainActor
struct ClipboardLookupsTests {
    /// A path is read once per opening of the clipboard, and the tile is told only when the answer changed.
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
        let path = "/Users/me/Documents/Acme/Quarterly_Budget_Review.pdf"

        #expect(facts.fact(for: path) == nil, "unknown until the first read lands")
        #expect(await eventuallyTrue { facts.fact(for: path)?.bytes == 1_000 })
        #expect(reads.load(ordering: .relaxed) == 1, "fresh: asking again doesn't read again")
        #expect(changes == 1)

        facts.markStale()
        #expect(facts.fact(for: path)?.bytes == 1_000, "the last answer shows while it's read again")
        #expect(await eventuallyTrue { reads.load(ordering: .relaxed) == 2 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changes == 1, "the same answer redraws nothing")

        size.store(2_000, ordering: .relaxed)
        facts.markStale()
        _ = facts.fact(for: path)
        #expect(await eventuallyTrue { facts.fact(for: path)?.bytes == 2_000 })
        #expect(changes == 2)
    }

    /// `[open_links]`'s app for a scheme, in any case; a change to the setting forgets what was looked up.
    @Test func linkAppsUseTheConfiguredAppAndForgetItWhenItChanges() async {
        let links = LinkApps()
        let textEdit = URL(filePath: "/System/Applications/TextEdit.app")
        links.configured = ["https": textEdit]

        #expect(links.app(for: "not a link") == nil)
        #expect(links.app(for: "HTTPS://acme.example") == nil, "looked up on a worker the first time")
        #expect(await eventuallyTrue { links.app(for: "https://acme.example")?.url == textEdit })
        #expect(links.app(for: "https://acme.example/budget")?.name == "TextEdit")

        links.configured = ["https": URL(filePath: "/Applications/Safari.app")]
        #expect(links.app(for: "https://acme.example") == nil, "looked up again")
        #expect(await eventuallyTrue { links.app(for: "https://acme.example")?.name == "Safari" })
    }
}
