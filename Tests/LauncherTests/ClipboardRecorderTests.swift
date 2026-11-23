import AppKit
import LauncherCore
import TestSupport
import Testing

@testable import Launcher

/// The recorder on a private, uniquely named pasteboard: these tests never read or change your clipboard.
struct ClipboardRecorderTests {
    @Test func recordsACopyWithTheAppItCameFrom() async throws {
        let folder = try TemporaryDirectory()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = ClipboardStore(folder: folder.url)
        let recorder = ClipboardRecorder(pasteboard: pasteboard, store: store) { _, _ in }
        recorder.start(timer: false)
        #expect(await recorder.check() == nil, "nothing new yet")

        let item = NSPasteboardItem()
        item.setString("docker compose up", forType: .string)
        item.setString("com.apple.Terminal", forType: .init(ClipReading.sourceMarker))
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let clip = try #require(await recorder.check())
        #expect(clip.kind == .text && clip.text == "docker compose up" && clip.source == "com.apple.Terminal")
        #expect(await recorder.check() == nil, "each change is read once")
        #expect(try await store.load().map(\.id) == [clip.id])
    }

    @Test func whatWasOnTheClipboardAtLaunchIsNotRecorded() async throws {
        let folder = try TemporaryDirectory()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("copied before Pith started", forType: .string)
        let recorder = ClipboardRecorder(pasteboard: pasteboard, store: ClipboardStore(folder: folder.url)) { _, _ in }
        recorder.start(timer: false)
        #expect(await recorder.check() == nil)
    }

    @Test func skipsPasswordsAndTemporaryCopies() async throws {
        let folder = try TemporaryDirectory()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = ClipboardStore(folder: folder.url)
        let recorder = ClipboardRecorder(pasteboard: pasteboard, store: store) { _, _ in }
        recorder.start(timer: false)

        for marker in ClipReading.skipMarkers.sorted() {
            let item = NSPasteboardItem()
            item.setString("correct horse battery staple", forType: .string)
            item.setData(Data(), forType: .init(marker))
            pasteboard.clearContents()
            pasteboard.writeObjects([item])
            #expect(await recorder.check() == nil, "\(marker)")
        }
        #expect(try await store.load().isEmpty)
    }

    @Test func recordsFilesImagesAndLinks() async throws {
        let folder = try TemporaryDirectory()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let recorder = ClipboardRecorder(pasteboard: pasteboard, store: ClipboardStore(folder: folder.url)) { _, _ in }
        recorder.start(timer: false)

        try folder.makeFile("Acme/Quarterly_Budget_Review.pdf")
        let report = folder.url.appending(path: "Acme/Quarterly_Budget_Review.pdf")
        pasteboard.clearContents()
        pasteboard.writeObjects([report as NSURL])
        let files = try #require(await recorder.check())
        #expect(files.kind == .files && files.text == report.path)

        let image = NSImage(size: NSSize(width: 30, height: 20), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let png = try #require(
            image.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap {
                NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:])
            })
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        let picture = try #require(await recorder.check())
        #expect(picture.kind == .image && picture.pixelWidth > 0)

        pasteboard.clearContents()
        pasteboard.setString("https://acme.example/quarterly", forType: .string)
        let link = try #require(await recorder.check())
        #expect(link.kind == .link && link.text == "https://acme.example/quarterly")
    }

    @Test func richTextWithoutPlainTextGetsItsText() async throws {
        let folder = try TemporaryDirectory()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let recorder = ClipboardRecorder(pasteboard: pasteboard, store: ClipboardStore(folder: folder.url)) { _, _ in }
        recorder.start(timer: false)

        let rtf = try NSAttributedString(string: "Quarterly budget").data(
            from: NSRange(location: 0, length: 16),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        pasteboard.clearContents()
        pasteboard.setData(rtf, forType: .rtf)
        let clip = try #require(await recorder.check())
        #expect(clip.kind == .richText && clip.text == "Quarterly budget")
    }

    @Test func pastingAClipBackMovesItInsteadOfCopyingIt() async throws {
        let folder = try TemporaryDirectory()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        let store = ClipboardStore(folder: folder.url)
        let recorder = ClipboardRecorder(pasteboard: pasteboard, store: store) { _, _ in }
        recorder.start(timer: false)

        let item = NSPasteboardItem()
        item.setString("<b>Acme</b>", forType: .html)
        item.setString("Acme", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let first = try #require(await recorder.check())
        pasteboard.clearContents()
        pasteboard.setString("something else", forType: .string)
        _ = await recorder.check()

        // What a paste from the history writes: the clip's own representations.
        let back = try await store.items(of: first.id).map { representations in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: .init(representation.type))
            }
            return item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(back)
        let again = try #require(await recorder.check())
        #expect(again.id == first.id)
        #expect(try await store.load().map(\.id) == [first.id, first.id + 1])
    }

    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: .init("PithTests-\(UUID().uuidString)"))
    }
}
