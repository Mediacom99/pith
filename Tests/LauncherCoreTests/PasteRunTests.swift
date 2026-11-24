import Foundation
import LauncherCore
import TestSupport
import Testing

/// Paste next's order (decision 64), on a real history in a temporary folder.
struct PasteRunTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func walksDownFromTheNewestAndSkipsWhatsGone() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        var clips: [Clip] = []
        for (minute, text) in ["Jane Appleseed", "jane@acme.example", "1 Infinite Loop", "+1 555 0100"].enumerated() {
            clips.append(try await store.add(content(text), from: nil, at: start + Double(minute) * 60))
        }
        var index = ClipboardIndex(clips: try await store.load())

        var run = PasteRun(index.clips, copies: 4, at: 100)
        #expect(run.next(in: index, at: 100)?.id == clips[3].id, "the last one copied first")
        #expect(run.next(in: index, at: 102)?.id == clips[2].id)
        index.remove([clips[1].id])
        #expect(run.next(in: index, at: 104)?.id == clips[0].id, "a deleted clip is skipped")
        #expect(run.next(in: index, at: 105) == nil, "past the oldest")
        #expect(run.next(in: index, at: 106) == nil)

        #expect(run.goesOn(copies: 4, at: 106 + PasteRun.pause - 1))
        #expect(!run.goesOn(copies: 4, at: 106 + PasteRun.pause), "a pause ends it")
        #expect(!run.goesOn(copies: 5, at: 107), "so does a new copy")
    }

    private func content(_ string: String) -> ClipContent {
        ClipContent(
            kind: .text, text: string,
            items: [[Representation(type: "public.utf8-plain-text", data: Data(string.utf8))]])
    }
}
