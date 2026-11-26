import AppKit
import LauncherCore
import TestSupport
import Testing

@testable import Launcher

/// A panel whose clipboard history is `clips` (oldest first), stored in `folder`. Delivering a clip is swapped for
/// `copied`, so the tests never touch the clipboard or type.
@MainActor
func clipboardPanel(
    _ folder: URL, _ clips: [(content: ClipContent, source: String?, minutesAgo: Double)], pinned: Set<Int> = [],
    copied: CopiedClips = CopiedClips()
) async throws -> LauncherPanel {
    let panel = makePanel(items: [])
    let store = ClipboardStore(folder: folder)
    for (position, clip) in clips.enumerated() {
        let stored = try await store.add(clip.content, from: clip.source, at: .now - clip.minutesAgo * 60)
        if pinned.contains(position) { try await store.setPinned(true, for: stored.id) }
    }
    let history = ClipboardHistory(store: store)
    await history.load()
    panel.launcher.clipboard = history
    panel.launcher.deliverClip = { clip, delivery in copied.deliveries.append((clip, delivery)) }
    return panel
}

/// What was pasted or copied, in order.
@MainActor final class CopiedClips {
    var deliveries: [(clip: Clip, delivery: ClipDelivery)] = []
    var clips: [Clip] { deliveries.map(\.clip) }
}

func text(_ string: String) -> ClipContent {
    ClipContent(
        kind: .text, text: string, items: [[Representation(type: "public.utf8-plain-text", data: Data(string.utf8))]])
}

struct ClipboardPanelTests {
    @Test func theClipboardListsTheNewestFirstUnderItsPreview() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(
            folder.url,
            [(text("first"), nil, 30), (text("second"), "com.apple.Terminal", 20), (text("third"), nil, 10)])
        panel.launcher.prepareToShow(.clipboard)

        #expect(panel.launcher.mode == .clipboard)
        #expect(titles(panel) == ["third", "second", "first"])
        #expect(panel.launcher.tableView.selectedRow == 0)
        #expect(panel.launcher.searchField.placeholderString == "Search clipboard")
        #expect(panel.launcher.tile.frame.height == Layout.clipboardTileHeight)
        #expect(panel.frame.height == Layout.expandedHeight, "the panel keeps its height")
        #expect(panel.launcher.tile.content.primary == "Copy", "no Accessibility access in tests")
        #expect(panel.launcher.tile.content.preview == .text("third", isBlank: false))
    }

    @Test func fiveWholeRowsFitUnderThePreview() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, (0..<9).map { (text("clip \($0)"), nil, Double(9 - $0)) })
        panel.launcher.prepareToShow(.clipboard)
        panel.layoutIfNeeded()
        let list = try #require(panel.launcher.tableView.enclosingScrollView)
        #expect(list.frame.minY == Layout.clipboardListTop)
        #expect(list.frame.height == 5 * Layout.rowHeight + Layout.listBottomInset)
        #expect(list.frame.maxY == Layout.expandedHeight)
    }

    @Test func typingPutsPinnedMatchesFirst() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(
            folder.url, [(text("acme pinned"), nil, 50), (text("acme newer"), nil, 5), (text("other"), nil, 1)],
            pinned: [0])
        panel.launcher.prepareToShow(.clipboard)
        #expect(titles(panel) == ["other", "acme newer", "acme pinned"], "no query: newest first, pins in place")

        await type("acme", in: panel)
        #expect(titles(panel) == ["acme pinned", "acme newer"])
    }

    @Test func aSearchWithNoMatchIsJustTheBar() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("Acme"), nil, 1)])
        panel.launcher.prepareToShow(.clipboard)
        await type("zzz", in: panel)
        #expect(panel.launcher.rows.isEmpty)
        #expect(panel.frame.height == Layout.barHeight)
    }

    @Test func anEmptyHistoryShowsTheTileAlone() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [])
        panel.launcher.prepareToShow(.clipboard)
        #expect(panel.launcher.rows.isEmpty)
        #expect(panel.frame.height == Layout.expandedHeight)
        #expect(!panel.launcher.tile.isHidden)
        #expect(panel.launcher.tile.content.name == "Nothing copied yet")
        #expect(panel.launcher.tile.content.primary.isEmpty, "no keys: there's nothing to act on")
    }

    @Test func cSpaceOpensTheClipboardAndBackspaceComesBack() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("Acme"), nil, 1)])
        var checks = 0
        panel.launcher.onShowClipboard = { checks += 1 }
        panel.launcher.prepareToShow()
        #expect(checks == 0)
        await type("c ", in: panel)
        #expect(panel.launcher.mode == .clipboard)
        #expect(checks == 1, "Accessibility is checked again, as ⌘⇧V does: it may have been given since")
        #expect(panel.launcher.searchField.stringValue.isEmpty)
        #expect(titles(panel) == ["Acme"])

        press("backspace", in: panel, held: true)
        #expect(panel.launcher.mode == .clipboard, "a held ⌫ that emptied the field doesn't run on into the launcher")
        press("down", in: panel, held: true)
        #expect(panel.launcher.tableView.selectedRow == 0, "↓ held repeats; one clip, so it stays")

        press("backspace", in: panel)
        #expect(panel.launcher.mode == .launcher)
        #expect(panel.launcher.tile.frame.height == Layout.tileHeight)
        #expect(panel.launcher.searchField.placeholderString == "Search")
    }

    @Test func returnPastesWithAccessAndCopiesWithoutAsking() async throws {
        let folder = try TemporaryDirectory()
        let copied = CopiedClips()
        let panel = try await clipboardPanel(
            folder.url, [(text("older"), nil, 10), (text("newest"), nil, 1)], copied: copied)
        var asked = 0
        panel.launcher.askForAccessibility = { asked += 1 }

        panel.launcher.prepareToShow(.clipboard)
        press("down", in: panel)
        press("return", in: panel)
        #expect(copied.deliveries.map(\.clip.text) == ["older"])
        #expect(copied.deliveries.map(\.delivery) == [.copy])
        #expect(asked == 1, "the first ⏎ without access asks for it")

        panel.launcher.reset()
        panel.launcher.prepareToShow(.clipboard)
        panel.launcher.toggleActions()
        await type("copy to", in: panel)
        press("return", in: panel)
        #expect(copied.deliveries.map(\.delivery) == [.copy, .copy])
        #expect(asked == 1, "Copy to Clipboard, chosen on purpose, doesn't ask")
        copied.deliveries.removeLast()

        panel.launcher.reset()
        panel.launcher.canPaste = true
        panel.launcher.prepareToShow(.clipboard)
        #expect(panel.launcher.tile.content.primary == "Paste")
        press("return", in: panel)
        #expect(copied.deliveries.map(\.delivery) == [.copy, .paste])
        #expect(copied.clips.last?.text == "newest")
    }

    /// Paste next (decision 64): each ⌃⌥V pastes the next clip down the history from the newest, without the panel,
    /// until the history runs out; a pause or a new copy starts again from the newest.
    @Test func pasteNextWalksDownFromTheNewest() async throws {
        let folder = try TemporaryDirectory()
        let copied = CopiedClips()
        let panel = try await clipboardPanel(
            folder.url,
            [(text("Jane Appleseed"), nil, 4), (text("jane@acme.example"), nil, 3), (text("Acme"), nil, 2)],
            copied: copied)
        let launcher = panel.launcher
        for time in [100.0, 101, 102, 103] { launcher.pasteNext(pressedAt: time) }
        #expect(copied.clips.map(\.text) == ["Acme", "jane@acme.example", "Jane Appleseed"], "then nothing")
        #expect(copied.deliveries.allSatisfy { $0.delivery == .pasteNext })
        #expect(!panel.isVisible && launcher.mode == .launcher, "the clipboard never opens")

        launcher.pasteNext(pressedAt: 103 + PasteRun.pause)
        #expect(copied.clips.last?.text == "Acme", "after a pause, the newest again")
        launcher.pasteNext(pressedAt: 104 + PasteRun.pause)
        #expect(copied.clips.last?.text == "jane@acme.example")

        launcher.clipboard?.recorded(
            try await launcher.clipboard!.store.add(text("Quarterly_Budget_Review"), from: nil, at: .now))
        launcher.pasteNext(pressedAt: 105 + PasteRun.pause)
        #expect(copied.clips.last?.text == "Quarterly_Budget_Review", "a new copy starts again from it")
    }

    @Test func commandKOffersWhatEachKindCanDo() async throws {
        let folder = try TemporaryDirectory()
        let rich = ClipContent(
            kind: .richText, text: "Acme",
            items: [
                [
                    Representation(type: "public.html", data: Data("<b>Acme</b>".utf8)),
                    Representation(type: "public.utf8-plain-text", data: Data("Acme".utf8)),
                ]
            ])
        let link = ClipContent(
            kind: .link, text: "https://acme.example",
            items: [[Representation(type: "public.utf8-plain-text", data: Data("https://acme.example".utf8))]])
        let files = ClipContent(
            kind: .files, text: "/Users/me/notes.md",
            items: [
                [Representation(type: "public.file-url", data: URL(filePath: "/Users/me/notes.md").dataRepresentation)]
            ])
        let panel = try await clipboardPanel(
            folder.url, [(files, nil, 4), (link, nil, 3), (rich, nil, 2), (text("plain"), nil, 1)], pinned: [0])
        panel.launcher.canPaste = true
        panel.launcher.prepareToShow(.clipboard)

        func actions(at row: Int) -> [ClipAction] {
            panel.launcher.reset()
            panel.launcher.prepareToShow(.clipboard)
            for _ in 0..<row { press("down", in: panel) }
            panel.launcher.toggleActions()
            return panel.launcher.rows.compactMap { if case .clipAction(let action) = $0 { action } else { nil } }
        }
        #expect(actions(at: 0) == [.paste, .copy, .save, .pin, .delete])
        #expect(actions(at: 1) == [.paste, .copy, .pastePlainText, .save, .pin, .delete])
        #expect(actions(at: 2) == [.paste, .copy, .openLink, .pin, .delete])
        #expect(actions(at: 3) == [.paste, .copy, .reveal, .unpin, .delete])
        #expect(panel.launcher.searchField.placeholderString == "Filter actions")
        #expect(panel.launcher.tile.content.name == "notes.md", "the clip stays on the tile")

        panel.launcher.canPaste = false
        #expect(actions(at: 1) == [.copy, .pastePlainText, .save, .pin, .delete])
        #expect(ClipAction.pastePlainText.title(canPaste: false, linkApp: nil) == "Copy as Plain Text")
    }

    @Test func pinningStaysOpenWithTheClipSelected() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(
            folder.url, [(text("one"), nil, 3), (text("two"), nil, 2), (text("three"), nil, 1)])
        panel.launcher.prepareToShow(.clipboard)
        press("down", in: panel)
        panel.launcher.toggleActions()
        try select(.pin, in: panel)
        press("return", in: panel)

        #expect(panel.launcher.sublist == nil, "back to the list")
        #expect(await eventuallyTrue { pinned(panel) == ["two"] })
        #expect(panel.launcher.tableView.selectedRow == 1, "the pinned clip stays selected")
    }

    @Test func deletingAPinnedClipWaitsForASecondReturn() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(
            folder.url, [(text("keep me"), nil, 2), (text("newest"), nil, 1)], pinned: [0])
        panel.launcher.prepareToShow(.clipboard)
        press("down", in: panel)
        panel.launcher.toggleActions()
        try select(.delete, in: panel)

        press("return", in: panel)
        #expect(panel.launcher.confirming)
        #expect(panel.launcher.tile.content.isDanger && panel.launcher.tile.content.secondary?.words == "Cancel")
        press("return", in: panel)
        #expect(await eventuallyTrue { titles(panel) == ["newest"] })
        #expect(try await panel.launcher.clipboard?.store.load().map(\.text) == ["newest"])
    }

    @Test func commandLettersRunTheActions() async throws {
        let folder = try TemporaryDirectory()
        let copied = CopiedClips()
        let panel = try await clipboardPanel(
            folder.url, [(text("keep me"), nil, 2), (text("newest"), nil, 1)], pinned: [0], copied: copied)
        panel.launcher.canPaste = true
        panel.launcher.prepareToShow(.clipboard)
        #expect(!press("cmd+w", in: panel), "only in an actions list")

        // Paste, Copy to Clipboard, Save as File, Pin, Delete: ⌘W is the second.
        panel.launcher.toggleActions()
        #expect(press("cmd+w", in: panel))
        #expect(copied.deliveries.map(\.delivery) == [.copy])
        #expect(!press("cmd+u", in: panel), "past the last action")

        // ⌘R pins the newest, even with a filter that hides Pin.
        panel.launcher.reset()
        panel.launcher.prepareToShow(.clipboard)
        panel.launcher.toggleActions()
        await type("del", in: panel)
        #expect(press("cmd+r", in: panel))
        #expect(await eventuallyTrue { pinned(panel) == ["newest", "keep me"] })

        // ⌘T deletes, at a second ⌘T (decision 74).
        panel.launcher.toggleActions()
        #expect(press("cmd+t", in: panel))
        #expect(panel.launcher.confirming)
        #expect(press("cmd+t", in: panel))
        #expect(await eventuallyTrue { titles(panel) == ["keep me"] })
    }

    @Test func saveAsFileWritesADatedFileAndSaysWhere() async throws {
        let folder = try TemporaryDirectory()
        let downloads = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("docker compose up\n"), nil, 1)])
        let now = try #require(
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 14, minute: 5)))
        panel.launcher.now = { now }
        panel.launcher.saveFolder = downloads.url
        let saved = SavedFiles()
        panel.launcher.reportSaved = { saved.files.append($0) }
        panel.launcher.prepareToShow(.clipboard)
        panel.launcher.toggleActions()
        try select(.save, in: panel)
        press("return", in: panel)

        #expect(await eventuallyTrue { !saved.files.isEmpty })
        let file = try #require(saved.files.first)
        #expect(file.lastPathComponent == "Clipboard 2026-11-23 at 14.05.txt")
        #expect(try String(contentsOf: file, encoding: .utf8) == "docker compose up\n")
        #expect(
            ClipFiles.destination(in: downloads.url, at: now, extension: "txt").lastPathComponent
                == "Clipboard 2026-11-23 at 14.05 2.txt", "a taken name is numbered")
    }

    @Test func noticesComeFirstAndTheNewestClipIsSelected() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("Acme"), nil, 1)])
        panel.launcher.clipboardNotices = [.cannotRead]
        panel.launcher.prepareToShow(.clipboard)
        #expect(titles(panel) == ["Pith can't read the clipboard", "Acme"])
        #expect(panel.launcher.tableView.selectedRow == 1)

        await type("acme", in: panel)
        #expect(titles(panel) == ["Acme"], "notices are for the full list, not a search")
    }

    @Test func returnOnThePausedNoticeResumesInPlace() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("Acme"), nil, 1)])
        var resolved: [ClipboardNotice] = []
        panel.launcher.resolveNotice = { resolved.append($0) }
        panel.launcher.clipboardNotices = [.paused]
        panel.launcher.prepareToShow(.clipboard)
        #expect(titles(panel) == ["Recording is paused", "Acme"])
        press("up", in: panel)
        #expect(panel.launcher.tile.content.primary == "Resume")

        press("return", in: panel)
        #expect(resolved == [.paused])
        panel.launcher.clipboardNotices = []
        #expect(titles(panel) == ["Acme"] && panel.launcher.tableView.selectedRow == 0)
    }

    @Test func retentionPrunesWhenItsSetAndAfterACopy() async throws {
        let folder = try TemporaryDirectory()
        let day = 24 * 60.0
        let panel = try await clipboardPanel(
            folder.url, [(text("pinned"), nil, 90 * day), (text("old"), nil, 40 * day), (text("new"), nil, 1)],
            pinned: [0])
        let history = try #require(panel.launcher.clipboard)
        #expect(history.index.count == 3, "no limits until the config is read")

        history.retention = .init(maxBytes: 2_000_000_000, maxAge: 30 * 86_400)
        #expect(await eventuallyTrue { history.index.clips.map(\.text) == ["new", "pinned"] }, "pins stay")

        history.stricterDelay = .zero
        history.retention = .init(maxBytes: 1, maxAge: 30 * 86_400)
        let copy = try await history.store.add(text("newest"), from: nil, at: .now)
        history.recorded(copy)
        #expect(await eventuallyTrue { history.index.clips.map(\.text) == ["pinned"] }, "the newest goes too")
    }

    /// An editor that saves as you type can save 3 on the way from 30 to 365: a stricter limit waits until it has
    /// stayed set, and a looser one applies at once (decision 76).
    @Test func aStricterLimitWaitsUntilItStaysSet() async throws {
        let folder = try TemporaryDirectory()
        let day = 24 * 60.0
        let panel = try await clipboardPanel(
            folder.url, [(text("ten days"), nil, 10 * day), (text("five days"), nil, 5 * day), (text("new"), nil, 1)])
        let history = try #require(panel.launcher.clipboard)
        history.stricterDelay = .milliseconds(300)
        history.retention = .init(maxBytes: 2_000_000_000, maxAge: 30 * 86_400)

        history.retention = .init(maxBytes: 2_000_000_000, maxAge: 3 * 86_400)
        try await Task.sleep(for: .milliseconds(100))
        history.retention = .init(maxBytes: 2_000_000_000, maxAge: 365 * 86_400)
        try await Task.sleep(for: .milliseconds(500))
        #expect(history.index.count == 3, "the half-typed 3 never applied")
        #expect(try await history.store.load().count == 3)

        history.retention = .init(maxBytes: 2_000_000_000, maxAge: 7 * 86_400)
        try await Task.sleep(for: .milliseconds(100))
        #expect(history.index.count == 3, "still waiting")
        #expect(await eventuallyTrue { history.index.clips.map(\.text) == ["new", "five days"] }, "then it applies")
    }

    @Test func clearingKeepsThePinnedClips() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(
            folder.url, [(text("pinned"), nil, 5), (text("gone"), nil, 1)], pinned: [0])
        let history = try #require(panel.launcher.clipboard)
        try await history.clear()
        #expect(history.index.clips.map(\.text) == ["pinned"])
        #expect(try await history.store.load().map(\.text) == ["pinned"])
    }

    @Test func resetGoesBackToTheLauncher() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("Acme"), nil, 1)])
        panel.launcher.prepareToShow(.clipboard)
        panel.launcher.reset()
        #expect(panel.launcher.mode == .launcher)
        #expect(panel.frame.height == Layout.barHeight)
        #expect(panel.launcher.tile.frame.height == Layout.tileHeight)
    }

    @Test func eachKindSaysWhatItIs() {
        func clip(_ kind: Clip.Kind, _ text: String, lines: Int? = nil, width: Int = 0, height: Int = 0) -> Clip {
            Clip(
                id: 1, kind: kind, copied: .now, source: nil, pinned: false, size: 0, text: text,
                lines: lines ?? Clip.lineCount(of: text), pixelWidth: width, pixelHeight: height)
        }
        let yaml = clip(.text, "\n  services:\n    web:   \t image: acme/site\n")
        #expect(ClipText.title(of: yaml) == ("services:", false))
        #expect(ClipText.title(of: yaml, query: "ACME") == ("web: image: acme/site", false))
        #expect(ClipText.detail(of: yaml) == "3 lines")
        #expect(ClipText.title(of: clip(.text, " \n\t")) == ("Spaces and line breaks", true))
        #expect(ClipText.title(of: clip(.link, "https://github.com/acme/site")).text == "github.com/acme/site")
        #expect(ClipText.host(of: clip(.link, "https://github.com/acme/site")) == "github.com")
        let image = clip(.image, "", width: 1920, height: 1080)
        #expect(ClipText.title(of: image).text == "Image" && ClipText.detail(of: image) == "1920 × 1080")
        #expect(ClipText.previewSize(of: image) == CGSize(width: 277, height: 156), "fitted into 320 × 156")
        #expect(ClipText.previewSize(of: clip(.image, "", width: 16, height: 16)) == CGSize(width: 8, height: 8))
        let files = clip(
            .files, "/Users/me/Documents/Acme/Quarterly_Budget_Review.pdf\n/Users/me/Documents/Acme/notes.md")
        #expect(ClipText.title(of: files).text == "Quarterly_Budget_Review.pdf and 1 more")
        #expect(ClipText.folders(of: files).hasSuffix("Documents/Acme"))
    }

    @Test func theAgeIsShortAndRecent() throws {
        let now = try #require(
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 14, minute: 30)))
        func ago(minutes: Double) -> String { ClipText.age(now - minutes * 60, now: now) }
        #expect(ago(minutes: 0.5) == "now")
        #expect(ago(minutes: 5) == "5 min")
        #expect(ago(minutes: 59) == "59 min")
        #expect(ago(minutes: 90).contains(":") || ago(minutes: 90).contains("PM") || ago(minutes: 90).contains("."))
        #expect(ago(minutes: 24 * 60) == "yesterday")
        #expect(ago(minutes: 3 * 24 * 60) == "Tue")
        #expect(ago(minutes: 20 * 24 * 60) == "Oct 31")
    }

    private func select(_ action: ClipAction, in panel: LauncherPanel) throws {
        let row = try #require(panel.launcher.rows.firstIndex(of: .clipAction(action)))
        for _ in 0..<row { press("down", in: panel) }
    }

    /// A copied file's facts are read again each time the clipboard opens: one deleted since says so.
    @Test func aCopiedFileDeletedSinceSaysSoNextTime() async throws {
        let folder = try TemporaryDirectory()
        let path = "/Users/me/Documents/Acme/Quarterly_Budget_Review.pdf"
        let files = ClipContent(
            kind: .files, text: path,
            items: [[Representation(type: "public.file-url", data: URL(filePath: path).dataRepresentation)]])
        let panel = try await clipboardPanel(folder.url, [(files, nil, 1)])
        panel.launcher.fileFacts = { _ in (true, 2_143_000) }
        panel.launcher.prepareToShow(.clipboard)
        #expect(await eventuallyTrue { panel.launcher.tile.content.kind.contains("MB") })
        #expect(!panel.launcher.tile.content.place.hasPrefix("No longer in"))

        panel.launcher.reset()
        panel.launcher.fileFacts = { _ in (false, nil) }
        panel.launcher.prepareToShow(.clipboard)
        #expect(await eventuallyTrue { panel.launcher.tile.content.place.hasPrefix("No longer in") })
    }

    /// A copy whose notice comes in after Clear removed it isn't put back as a row whose clip is gone.
    @Test func aCopyClearedBeforeItsNoticeStaysGone() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let history = ClipboardHistory(store: store)
        await history.load()
        let late = try await store.add(text("copied as Clear ran"), from: nil, at: .now)
        try await history.clear()
        history.recorded(late)
        #expect(history.index.count == 0)
    }

    /// A copy of many files lists them, not the first 4,096 characters' worth: the count is the whole list's, and no
    /// path is cut.
    @Test func aCopyOfManyFilesKeepsItsPaths() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let paths = (0..<3_000).map { "/Users/me/Documents/Acme/Quarterly Budget Review/scan-\($0).pdf" }
        let items = paths.map { [Representation(type: "public.file-url", data: URL(filePath: $0).dataRepresentation)] }
        _ = try await store.add(
            ClipContent(kind: .files, text: paths.joined(separator: "\n"), items: items), from: nil, at: .now)
        let clip = try #require(try await store.load().first)
        let listed = ClipText.paths(of: clip)
        #expect(listed.count > 2_000)
        #expect(listed == Array(paths.prefix(listed.count)), "none cut short")
        #expect(ClipText.title(of: clip).text == "scan-0.pdf and \(2_999.formatted()) more")
    }

    /// A copy that lands while you choose keeps your clip selected: ⏎ pastes what the tile shows.
    @Test func aCopyLandingWhileOpenKeepsTheSelection() async throws {
        let folder = try TemporaryDirectory()
        let copied = CopiedClips()
        let panel = try await clipboardPanel(
            folder.url, [(text("older"), nil, 10), (text("newer"), nil, 5)], copied: copied)
        panel.launcher.prepareToShow(.clipboard)
        press("down", in: panel)
        #expect(panel.launcher.tableView.selectedRow == 1)

        let history = try #require(panel.launcher.clipboard)
        history.recorded(try await history.store.add(text("just copied"), from: nil, at: .now))
        #expect(panel.launcher.rows.count == 3)
        #expect(panel.launcher.tableView.selectedRow == 2)
        press("return", in: panel)
        #expect(copied.clips.map(\.text) == ["older"])

        panel.launcher.reset()
        panel.launcher.prepareToShow(.clipboard)
        #expect(panel.launcher.tableView.selectedRow == 0, "opened again: the newest")
    }

    /// A copy that lands while a clip's actions are listed shows on going back, with that clip still selected.
    @Test func aCopyBehindTheActionsShowsOnGoingBack() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("older"), nil, 10), (text("newer"), nil, 5)])
        panel.launcher.prepareToShow(.clipboard)
        press("down", in: panel)
        panel.launcher.toggleActions()

        let history = try #require(panel.launcher.clipboard)
        history.recorded(try await history.store.add(text("just copied"), from: nil, at: .now))
        #expect(panel.launcher.sublist != nil, "the actions stay up")
        press("escape", in: panel)
        #expect(titles(panel) == ["just copied", "newer", "older"])
        #expect(panel.launcher.tableView.selectedRow == 2, "still on older")
    }

    /// A shortcut never deletes in one press, pinned or not; ⏎ on the Delete row does (decision 74).
    @Test func deletingByShortcutWaitsForASecondPress() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("older"), nil, 2), (text("newest"), nil, 1)])
        panel.launcher.canPaste = true
        panel.launcher.prepareToShow(.clipboard)
        panel.launcher.toggleActions()

        // Paste, Copy to Clipboard, Save as File, Pin, Delete: ⌘T is the fifth.
        #expect(press("cmd+t", in: panel))
        #expect(panel.launcher.confirming && panel.launcher.tile.content.isDanger)
        press("escape", in: panel)
        #expect(!panel.launcher.confirming && panel.launcher.sublist != nil, "⎋ cancels it, not the actions")
        #expect(try await panel.launcher.clipboard?.store.load().count == 2, "nothing deleted")

        #expect(press("cmd+t", in: panel) && press("cmd+t", in: panel))
        #expect(await eventuallyTrue { titles(panel) == ["older"] })

        panel.launcher.toggleActions()
        try select(.delete, in: panel)
        press("return", in: panel)
        #expect(await eventuallyTrue { titles(panel).isEmpty }, "⏎ on the row deletes at once")
    }

    /// Clips another program deleted or copied again are gone, or on top, when the clipboard opens next (decision 73).
    @Test func anotherProgramsChangesShowWhenTheClipboardOpens() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(
            folder.url, [(text("one"), nil, 30), (text("two"), nil, 20), (text("three"), nil, 10)])
        panel.launcher.prepareToShow(.clipboard)
        #expect(titles(panel) == ["three", "two", "one"])
        panel.launcher.reset()

        let other = ClipboardStore(folder: folder.url)
        let two = try #require(try await other.load().first { $0.text == "two" })
        try await other.delete(two.id)
        _ = try await other.add(text("one"), from: nil, at: .now)
        panel.launcher.prepareToShow(.clipboard)
        #expect(await eventuallyTrue { titles(panel) == ["one", "three"] })
    }

    /// A clip another program deleted since the clipboard opened says why it fails, and leaves the list.
    @Test func aClipGoneFromTheDatabaseLeavesTheListWhenUsed() async throws {
        let folder = try TemporaryDirectory()
        let downloads = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("older"), nil, 10), (text("gone"), nil, 5)])
        var failures: [String] = []
        panel.launcher.reportFailure = { title, _, reason in failures.append("\(title): \(reason)") }
        panel.launcher.saveFolder = downloads.url
        panel.launcher.prepareToShow(.clipboard)
        let history = try #require(panel.launcher.clipboard)
        try await ClipboardStore(folder: folder.url).delete(try #require(history.index.clips.first).id)

        panel.launcher.toggleActions()
        try select(.save, in: panel)
        press("return", in: panel)
        #expect(await eventuallyTrue { !failures.isEmpty })
        #expect(failures == ["Couldn't save the clip: it's no longer in the history"])
        #expect(history.index.clips.map(\.text) == ["older"])
    }

    /// Paste and Copy to Clipboard, for a clip that's gone, fail before they reach the clipboard and drop it.
    @Test func pastingAClipThatsGoneDropsItFromTheList() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let kept = try await store.add(text("kept"), from: nil, at: .now - 60)
        let gone = try await store.add(text("gone"), from: nil, at: .now)
        let history = ClipboardHistory(store: store)
        await history.load()
        try await ClipboardStore(folder: folder.url).delete(gone.id)
        // Gone before the paster looks, so it fails without writing the clipboard.
        let failure = await #expect(throws: ClipboardStore.Failure.self) { try await store.items(of: gone.id) }
        try #require(failure?.isGone == true)

        let paster = ClipPaster()
        var failures: [String] = []
        paster.onFailure = { title, reason in failures.append("\(title): \(reason)") }
        paster.deliver(gone, .copy, from: history)
        #expect(await eventuallyTrue { !failures.isEmpty })
        #expect(failures == ["Couldn't copy the clip: it's no longer in the history"])
        #expect(history.index.clips.map(\.id) == [kept.id])
    }

    /// A thumbnail that can't be read is asked for once and draws nothing new: a redraw would ask again, forever,
    /// with a core busy until Pith quits.
    @Test func anUnreadableThumbnailIsAskedForOnce() async throws {
        let folder = try TemporaryDirectory()
        let store = ClipboardStore(folder: folder.url)
        let clip = try await store.add(
            ClipContent(kind: .image, text: "", items: [], image: try flatPNG(width: 30, height: 20)), from: nil,
            at: .now)
        try FileManager.default.removeItem(at: store.rowThumbnail(of: clip.id))
        let images = ClipImages()
        var redraws = 0
        images.onChange = { redraws += 1 }

        #expect(images.row(clip, store: store) == nil)
        #expect(images.isLoading)
        for _ in 0..<200 where images.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!images.isLoading)
        #expect(images.row(clip, store: store) == nil)
        #expect(!images.isLoading, "not read again")
        #expect(redraws == 0)

        #expect(images.preview(clip, store: store) == nil)
        for _ in 0..<200 where images.isLoading { try await Task.sleep(for: .milliseconds(5)) }
        #expect(images.preview(clip, store: store) != nil, "the preview, still there, loads")
        #expect(redraws == 1)
    }

    private func pinned(_ panel: LauncherPanel) -> [String] {
        panel.launcher.rows.compactMap { if case .clip(let clip) = $0, clip.pinned { clip.text } else { nil } }
    }

    private func titles(_ panel: LauncherPanel) -> [String] {
        panel.launcher.rows.map {
            switch $0 {
            case .clip(let clip): ClipText.title(of: clip).text
            case .notice(let notice): LauncherViewController.noticeTitle(notice)
            case .item(let item): item.name
            case .action(let action): "\(action)"
            case .problem(let message): message
            case .clipAction(let action): action.title(canPaste: panel.launcher.canPaste, linkApp: nil)
            }
        }
    }
}

@MainActor final class SavedFiles {
    var files: [URL] = []
}

/// Polls `condition` until it holds or a few seconds pass, for work that hops through the store's queue.
@MainActor func eventuallyTrue(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(25)) }
    return condition()
}
