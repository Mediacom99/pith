import Foundation
import LauncherCore
import TestSupport
import Testing

/// Paste next's order (decision 63), on a real history in a temporary folder.
struct PasteRunTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func pastesWhatWasCopiedAfterInOrderAndSkipsWhatsGone() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        var clips: [Clip] = []
        for (minute, text) in ["Jane Appleseed", "jane@acme.example", "1 Infinite Loop", "+1 555 0100"].enumerated() {
            clips.append(try await store.add(content(text), from: nil, at: start + Double(minute) * 60))
        }
        var index = ClipboardIndex(clips: try await store.load())

        var run = PasteRun(after: clips[0].id, in: index.clips)
        // Pasting moves a clip to the top; the run keeps the order it started with.
        index.insert(try await store.touch(clips[0].id, at: start + 600))
        #expect(run.next(in: index)?.id == clips[1].id)
        index.insert(try await store.touch(clips[1].id, at: start + 660))
        index.insert(try await store.add(content("copied meanwhile"), from: nil, at: start + 700))
        index.remove([clips[2].id])
        #expect(run.next(in: index)?.id == clips[3].id, "a deleted clip is skipped")
        #expect(run.isEmpty && run.next(in: index) == nil, "the newest ends it, without what was copied meanwhile")

        #expect(PasteRun(after: index.clips[0].id, in: index.clips).isEmpty, "nothing comes after the newest")
        #expect(PasteRun(after: 9_999, in: index.clips).isEmpty)
    }

    private func content(_ string: String) -> ClipContent {
        ClipContent(
            kind: .text, text: string,
            items: [[Representation(type: "public.utf8-plain-text", data: Data(string.utf8))]])
    }
}
