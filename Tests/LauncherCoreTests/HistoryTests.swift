import Foundation
import Testing

@testable import LauncherCore

private let now = Date(timeIntervalSince1970: 2_000_000_000)

private func daysAgo(_ days: Double) -> Date {
    now.addingTimeInterval(-days * 86_400)
}

struct HistoryTests {
    @Test func recentListsNewestFirst() {
        var history = History()
        history.record("a", at: daysAgo(3))
        history.record("b", at: daysAgo(1))
        history.record("c", at: daysAgo(2))
        history.record("a", at: daysAgo(0))
        #expect(history.recent(limit: 10) == ["a", "b", "c"])
        #expect(history.recent(limit: 2) == ["a", "b"])
    }

    @Test func frecencyGrowsWithUseAndFadesWithAge() {
        var history = History()
        history.record("daily", at: daysAgo(1))
        history.record("daily", at: daysAgo(0))
        history.record("once", at: daysAgo(0))
        history.record("old", at: daysAgo(200))
        history.record("old", at: daysAgo(150))
        #expect(history.frecency(of: "daily", now: now) > history.frecency(of: "once", now: now))
        #expect(history.frecency(of: "once", now: now) > history.frecency(of: "old", now: now))
        #expect(history.frecency(of: "never", now: now) == 0)
    }

    @Test func boostIsCappedSoBetterMatchesStillWin() {
        #expect(History.boost(frecency: 0) == 0)
        #expect(History.boost(frecency: 100) == 12)
        #expect(History.boost(frecency: 1_000_000) == 48)
    }

    @Test func boostsAlignWithTheIndex() {
        let index = SearchIndex(
            items: ["Safari", "Slack"].map { Item(name: $0, appAt: URL(filePath: "/A/\($0).app")) })
        var history = History()
        history.record("/A/Slack.app", at: now)
        history.record("/gone/Old.app", at: now)
        let boosts = history.boosts(for: index, now: now)
        #expect(boosts.count == 2)
        #expect(boosts[index.position(of: "/A/Slack.app")!] > 0)
        #expect(boosts[index.position(of: "/A/Safari.app")!] == 0)
    }

    @Test func keepsTheLatestOpensAndForgetsTheLeastUsed() {
        var history = History()
        for day in 0..<30 { history.record("busy", at: daysAgo(Double(day))) }
        for item in 0..<History.capacity { history.record("item \(item)", at: daysAgo(100)) }
        #expect(history.recent(limit: 1000).count == History.capacity)
        #expect(history.frecency(of: "busy", now: now) > 0, "the most used item survives")
    }

    @Test func forgetsDeletedFilesAndWhatWasInDeletedFolders() {
        var history = History()
        for id in [
            "file:/u/a.txt", "folder:/u/Docs", "file:/u/Docs/b.txt", "file:/u/Docs2/c.txt", "/Applications/X.app",
        ] {
            history.record(id, at: now)
        }
        history.forget(paths: ["/u/a.txt", "/u/Docs"])
        #expect(Set(history.recent(limit: 10)) == ["file:/u/Docs2/c.txt", "/Applications/X.app"])
    }

    @Test func fileBoostsAreByPath() {
        var history = History()
        history.record("file:/u/a.txt", at: now)
        history.record("/Applications/X.app", at: now)
        #expect(history.fileBoosts(now: now) == ["/u/a.txt": 12])
    }

    @Test func roundTripsThroughJSON() throws {
        var history = History()
        history.record("a", at: now)
        let decoded = try JSONDecoder().decode(History.self, from: JSONEncoder().encode(history))
        #expect(decoded == history)
    }
}
