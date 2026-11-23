import CoreGraphics
import Foundation
import ImageIO
import LauncherCore
import TestSupport
import Testing
import UniformTypeIdentifiers

struct ClipboardStoreTests {
    let start = Date(timeIntervalSince1970: 1_790_000_000)
    let day: TimeInterval = 86_400

    @Test func storesClipsAndLoadsThemNewestFirst() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let first = try await store.add(text("docker compose up"), from: "com.apple.Terminal", at: start)
        let second = try await store.add(text("Quarterly_Budget_Review\nline two\n"), from: nil, at: start + 60)

        #expect(first.kind == .text && first.source == "com.apple.Terminal" && !first.pinned && first.lines == 1)
        #expect(first.size == 2 * "docker compose up".utf8.count, "the text and its representation")
        #expect(second.lines == 2 && second.source == nil && second.copied == start + 60)
        #expect(try await store.load() == [second, first])
    }

    @Test func copyingTheSameContentAgainMovesItToTheTopAndKeepsItsPin() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let ssh = try await store.add(text("ssh deploy@acme.example"), from: "com.apple.Terminal", at: start)
        try await store.setPinned(true, for: ssh.id)
        let other = try await store.add(text("Acme"), from: nil, at: start + 60)

        let again = try await store.add(text("ssh deploy@acme.example"), from: "com.apple.Notes", at: start + 120)
        #expect(again.id == ssh.id && again.pinned)
        #expect(again.source == "com.apple.Notes" && again.copied == start + 120)
        #expect(try await store.load().map(\.id) == [ssh.id, other.id])
    }

    @Test func aPasteGetsBackEveryRepresentationItWasCopiedWith() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let rich = ClipContent(
            kind: .richText, text: "Hello",
            items: [
                [
                    Representation(type: "public.rtf", data: Data(#"{\rtf1 Hello}"#.utf8)),
                    Representation(type: "public.utf8-plain-text", data: Data("Hello".utf8)),
                ],
                [Representation(type: "com.acme.empty", data: Data())],
            ])
        let clip = try await store.add(rich, from: nil, at: start)
        #expect(try await store.items(of: clip.id) == rich.items)
    }

    @Test func imagesAreFilesWithThumbnailsAtTheirExactSizes() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let png = try flatPNG(width: 1000, height: 500)
        let html = Representation(type: "public.html", data: Data("<img src=chart.png>".utf8))
        let clip = try await store.add(
            ClipContent(kind: .image, text: "", items: [[html]], image: png), from: nil, at: start)

        #expect(clip.pixelWidth == 1000 && clip.pixelHeight == 500)
        #expect(try Data(contentsOf: store.imageFile(of: clip.id)) == png)
        #expect(try pixels(of: store.rowThumbnail(of: clip.id)) == [40, 40])
        #expect(try pixels(of: store.previewThumbnail(of: clip.id)) == [624, 312], "fitted into 640 × 312")
        let items = try await store.items(of: clip.id)
        #expect(items == [[Representation(type: "public.png", data: png), html]], "the image comes first")

        // A small image fills its row thumbnail but is never scaled up in the preview.
        let icon = try await store.add(
            ClipContent(kind: .image, text: "", items: [], image: try flatPNG(width: 16, height: 16)), from: nil,
            at: start)
        #expect(try pixels(of: store.rowThumbnail(of: icon.id)) == [40, 40])
        #expect(try pixels(of: store.previewThumbnail(of: icon.id)) == [16, 16])
        #expect(try await store.items(of: icon.id).map { $0.map(\.type) } == [["public.png"]])
    }

    @Test func refusesAnImageItCantRead() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let broken = ClipContent(kind: .image, text: "", items: [], image: Data("not a png".utf8))
        await #expect(throws: ClipboardStore.Failure.self) { try await store.add(broken, from: nil, at: start) }
        #expect(try await store.load().isEmpty)
    }

    @Test func pruningDropsOldClipsThenTheOldestUntilItFitsButNeverPins() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        var clips: [Clip] = []
        for number in 0..<5 {
            clips.append(try await store.add(text("clip \(number)"), from: nil, at: start + Double(number) * day))
        }
        try await store.setPinned(true, for: clips[0].id)
        let now = start + 4 * day

        let tooOld = try await store.prune(.init(maxBytes: .max, maxAge: 1.5 * day), now: now)
        #expect(tooOld == [clips[1].id, clips[2].id], "the pinned clip is older still, and stays")

        let tooBig = try await store.prune(.init(maxBytes: 2 * clips[3].size, maxAge: .infinity), now: now)
        #expect(tooBig == [clips[3].id], "the oldest unpinned clip goes first")
        #expect(try await store.load().map(\.id) == [clips[4].id, clips[0].id])
    }

    @Test func deletingAnImageRemovesItsFiles() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let clip = try await store.add(
            ClipContent(kind: .image, text: "", items: [], image: try flatPNG(width: 80, height: 60)), from: nil,
            at: start)
        let files = [
            store.imageFile(of: clip.id), store.rowThumbnail(of: clip.id), store.previewThumbnail(of: clip.id),
        ]
        #expect(files.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        try await store.delete(clip.id)
        #expect(!files.contains { FileManager.default.fileExists(atPath: $0.path) })
        #expect(try await store.load().isEmpty)
        #expect(try await store.items(of: clip.id).isEmpty)
    }

    @Test func clearingKeepsPinnedClips() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let kept = try await store.add(text("kept"), from: nil, at: start)
        let gone = try await store.add(text("gone"), from: nil, at: start + 60)
        try await store.setPinned(true, for: kept.id)

        #expect(try await store.clear() == [gone.id])
        #expect(try await store.load().map(\.id) == [kept.id])
    }

    @Test func theHistoryIsStillThereAfterRelaunch() async throws {
        let folder = try TemporaryDirectory()
        let saved: [Clip]
        do {
            let store = ClipboardStore(folder: folder.url)
            let clip = try await store.add(text("Acme"), from: "com.apple.Safari", at: start)
            try await store.setPinned(true, for: clip.id)
            _ = try await store.add(
                ClipContent(kind: .image, text: "", items: [], image: try flatPNG(width: 30, height: 20)), from: nil,
                at: start + 60)
            saved = try await store.load()
        }
        let reopened = ClipboardStore(folder: folder.url)
        #expect(try await reopened.load() == saved)
        #expect(saved.count == 2 && saved[1].pinned)
    }

    @Test func aPauseLastsThroughARelaunch() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url.appending(path: "clipboard"))
        #expect(await !store.isPaused(), "recording by default, before the folder exists")
        try await store.setPaused(true)
        #expect(await ClipboardStore(folder: store.folder).isPaused())
        try await store.setPaused(false)
        #expect(await !ClipboardStore(folder: store.folder).isPaused())
    }

    @Test func aLongTextIsKeptWholeOnDiskAndOnlyItsStartInMemory() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let log = String(repeating: "0123456789\n", count: 1000)
        let clip = try await store.add(text(log), from: nil, at: start)

        #expect(clip.text.count == Clip.textLimit && log.hasPrefix(clip.text))
        #expect(clip.lines == 1000)
        #expect(try await store.text(of: clip.id) == log)
    }

    @Test func removesImageFilesACrashLeftBehind() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let clip = try await store.add(
            ClipContent(kind: .image, text: "", items: [], image: try flatPNG(width: 30, height: 20)), from: nil,
            at: start)
        let orphan = store.imageFile(of: clip.id + 1)
        try Data("left over".utf8).write(to: orphan)

        _ = try await store.load()
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(FileManager.default.fileExists(atPath: store.imageFile(of: clip.id).path))
    }

    @Test func countsLines() {
        #expect(Clip.lineCount(of: "") == 0)
        #expect(Clip.lineCount(of: "one") == 1)
        #expect(Clip.lineCount(of: "one\n") == 1)
        #expect(Clip.lineCount(of: "one\ntwo") == 2)
        #expect(Clip.lineCount(of: "\n\n") == 2)
    }

    // MARK: Helpers

    private func text(_ string: String) -> ClipContent {
        ClipContent(
            kind: .text, text: string,
            items: [[Representation(type: "public.utf8-plain-text", data: Data(string.utf8))]])
    }

    /// An image file's width and height in pixels.
    private func pixels(of file: URL) throws -> [Int] {
        let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight].map { properties[$0] as? Int ?? 0 }
    }
}
