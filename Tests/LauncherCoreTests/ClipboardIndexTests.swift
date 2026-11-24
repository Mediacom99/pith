import Foundation
import LauncherCore
import Testing

struct ClipboardIndexTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func withoutAQueryItListsTheNewestFirstWithPinsInTheirPlace() {
        let index = ClipboardIndex(clips: [
            clip(1, "ssh deploy@acme.example", minutes: 0, pinned: true), clip(2, "Acme", minutes: 1),
            clip(3, "Quarterly budget", minutes: 2),
        ])
        #expect(ids(index, index.search("", limit: 10)) == [3, 2, 1])
        #expect(ids(index, index.search("  ", limit: 2)) == [3, 2])
    }

    @Test func typingPutsPinnedMatchesFirst() {
        var clips = [clip(1, "acme pinned long ago", minutes: 0, pinned: true)]
        for number in 2...60 { clips.append(clip(Int64(number), "acme note \(number)", minutes: number)) }
        let index = ClipboardIndex(clips: clips)
        #expect(ids(index, index.search("acme", limit: 3)) == [1, 60, 59], "the pin is found past the limit")
    }

    @Test func wordsMatchInAnyOrderIgnoringCaseAndAccents() {
        let index = ClipboardIndex(clips: [
            clip(1, "Le menu du Café", minutes: 0), clip(2, "menu", minutes: 1),
            clip(3, "docker compose up", minutes: 2),
        ])
        #expect(ids(index, index.search("CAFE menu", limit: 10)) == [1])
        #expect(ids(index, index.search("compose dock", limit: 10)) == [3])
        #expect(ids(index, index.search("menu", limit: 10)) == [2, 1])
        #expect(index.search("dcoker", limit: 10).isEmpty, "words match as written, not fuzzily")
    }

    @Test func filesMatchByNameAndImagesHaveNoText() {
        let files = Clip(
            id: 1, kind: .files, copied: start, source: "com.apple.finder", pinned: false, size: 0,
            text: "/Users/me/Documents/Acme/Quarterly_Budget_Review.pdf\n/Users/me/Documents/Acme/notes.md", lines: 2)
        let image = Clip(
            id: 2, kind: .image, copied: start, source: nil, pinned: false, size: 0, text: "", lines: 0,
            pixelWidth: 1920, pixelHeight: 1080)
        let index = ClipboardIndex(clips: [files, image])
        #expect(ids(index, index.search("budget", limit: 10)) == [1])
        #expect(ids(index, index.search("notes.md", limit: 10)) == [1])
        #expect(index.search("documents", limit: 10).isEmpty, "folders aren't searched")
        #expect(index.search("1920", limit: 10).isEmpty)
    }

    @Test func aCopyMovesToItsPlaceAndRetentionRemoves() {
        var index = ClipboardIndex(clips: [clip(1, "one", minutes: 0), clip(2, "two", minutes: 1)])
        index.insert(clip(3, "three", minutes: 2))
        #expect(ids(index, Array(index.clips.indices)) == [3, 2, 1])

        // Copied again: the same clip, newer.
        index.insert(clip(1, "one", minutes: 3))
        #expect(ids(index, Array(index.clips.indices)) == [1, 3, 2])
        #expect(ids(index, index.search("one", limit: 10)) == [1])

        index.setPinned(true, for: 2)
        index.remove([3])
        #expect(ids(index, Array(index.clips.indices)) == [1, 2])
        #expect(index.clips[1].pinned)
        #expect(index.position(of: 3) == nil)
    }

    @Test func findsTheLineThatMatches() {
        let text = "services:\n  web:\n    image: acme/site\n    ports: [8080]\n"
        #expect(ClipboardIndex.matchingLine(in: text, for: "ACME") == "    image: acme/site")
        #expect(ClipboardIndex.matchingLine(in: text, for: "nothing here") == nil)
        #expect(ClipboardIndex.matchingLine(in: text, for: "") == nil)
    }

    private func clip(_ id: Int64, _ text: String, minutes: Int, pinned: Bool = false) -> Clip {
        Clip(
            id: id, kind: .text, copied: start + Double(minutes) * 60, source: nil, pinned: pinned,
            size: text.utf8.count, text: text, lines: Clip.lineCount(of: text))
    }

    private func ids(_ index: ClipboardIndex, _ positions: [Int]) -> [Int64] {
        positions.map { index.clips[$0].id }
    }
}
