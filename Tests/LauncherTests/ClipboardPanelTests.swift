import AppKit
import LauncherCore
import TestSupport
import Testing

@testable import Launcher

/// A panel whose clipboard history is `clips` (oldest first), stored in `folder`. ⏎ is swapped for `copied`, so the
/// tests never touch the clipboard.
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
    panel.launcher.copyClip = { copied.clips.append($0) }
    return panel
}

/// What ⏎ copied, in order.
@MainActor final class CopiedClips {
    var clips: [Clip] = []
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
        #expect(panel.launcher.stage.frame.height == Layout.clipboardTileHeight)
        #expect(panel.frame.height == Layout.expandedHeight, "the panel keeps its height")
        #expect(panel.launcher.stage.content.primary == "Copy")
        #expect(panel.launcher.stage.content.preview == .text("third", isBlank: false))
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
        #expect(!panel.launcher.stage.isHidden)
        #expect(panel.launcher.stage.content.name == "Nothing copied yet")
        #expect(panel.launcher.stage.content.primary.isEmpty, "no keys: there's nothing to act on")
    }

    @Test func cSpaceOpensTheClipboardAndBackspaceComesBack() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("Acme"), nil, 1)])
        panel.launcher.prepareToShow()
        await type("c ", in: panel)
        #expect(panel.launcher.mode == .clipboard)
        #expect(panel.launcher.searchField.stringValue.isEmpty)
        #expect(titles(panel) == ["Acme"])

        press(#selector(NSResponder.deleteBackward(_:)), in: panel)
        #expect(panel.launcher.mode == .launcher)
        #expect(panel.launcher.stage.frame.height == Layout.tileHeight)
        #expect(panel.launcher.searchField.placeholderString == "Search")
    }

    @Test func returnCopiesTheSelectedClipBack() async throws {
        let folder = try TemporaryDirectory()
        let copied = CopiedClips()
        let panel = try await clipboardPanel(
            folder.url, [(text("older"), nil, 10), (text("newest"), nil, 1)], copied: copied)
        panel.launcher.prepareToShow(.clipboard)
        press(#selector(NSResponder.moveDown(_:)), in: panel)
        press(#selector(NSResponder.insertNewline(_:)), in: panel)
        #expect(copied.clips.map(\.text) == ["older"])
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

    @Test func resetGoesBackToTheLauncher() async throws {
        let folder = try TemporaryDirectory()
        let panel = try await clipboardPanel(folder.url, [(text("Acme"), nil, 1)])
        panel.launcher.prepareToShow(.clipboard)
        panel.launcher.reset()
        #expect(panel.launcher.mode == .launcher)
        #expect(panel.frame.height == Layout.barHeight)
        #expect(panel.launcher.stage.frame.height == Layout.tileHeight)
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

    private func titles(_ panel: LauncherPanel) -> [String] {
        panel.launcher.rows.map {
            switch $0 {
            case .clip(let clip): ClipText.title(of: clip).text
            case .notice(let notice): LauncherViewController.noticeTitle(notice)
            case .item(let item): item.name
            case .action(let action): "\(action)"
            case .problem(let message): message
            }
        }
    }
}
