import AppKit
import LauncherCore
import Testing

@testable import Launcher

/// Pictures of the panel in its main states, light and dark, for design reviews: `make snapshots` writes them to
/// docs/snapshots/. Real panels, drawn but never put on screen, with made-up history and files; only the built-in apps'
/// icons are real. Finder is the one app expected to be running, so it's the one with the running dot.
@Suite(.serialized) struct PanelSnapshots {
    private static let folder = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/snapshots")

    private static let apps: [Item] =
        [
            "Calculator", "Calendar", "Chess", "Font Book", "Image Capture", "Maps", "Photo Booth", "Preview",
            "Stickies", "TextEdit",
        ].map { Item(name: $0, appAt: URL(filePath: "/System/Applications/\($0).app")) }
        + [Item(name: "Finder", appAt: URL(filePath: "/System/Library/CoreServices/Finder.app"))]

    private static func app(_ name: String) -> Item { apps.first { $0.name == name }! }

    private static func file(_ path: String) -> Item {
        Item(path: NSHomeDirectory() + "/" + path, isFolder: false)
    }

    /// Eight recent items, newest first: the selected PDF, then a mix of apps, files and a folder.
    private static let recent: [Item] = [
        file("Documents/Acme/Quarterly_Budget_Review.pdf"),
        app("Finder"),
        Item(path: NSHomeDirectory() + "/Documents/Acme", isFolder: true),
        app("Calculator"),
        file("Documents/Acme/Brand/Logo.png"),
        app("TextEdit"),
        file("Desktop/Ideas.txt"),
        app("Calendar"),
    ]

    /// Names too long for a row, to see where they're cut: the selected file deep in its folders, a folder, a long
    /// file name, then short ones to compare.
    private static let longNames: [Item] = [
        file(
            "Documents/Acme/Finance/Reports/2026/Q3/Board Meetings/Archive/"
                + "Quarterly_Budget_Review_Final_Version_Approved_by_the_Board_v14_revised.pdf"),
        Item(
            path: NSHomeDirectory()
                + "/Documents/Acme/Brand/Guidelines and Assets for the Spring Product Launch Campaign",
            isFolder: true),
        file("Desktop/Notes from the planning session about the onboarding flow and the new pricing page.txt"),
        app("Finder"),
        app("Calculator"),
        file("Documents/Acme/Brand/Logo.png"),
        app("TextEdit"),
        app("Calendar"),
    ]

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func states(appearance: NSAppearance.Name) async throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: appearance)
        defer { NSApp.appearance = nil }
        let suffix = appearance == .darkAqua ? "dark" : "light"

        let bar = try await panel(emptyState: .none)
        bar.launcher.prepareToShow()
        try await snapshot(bar, "bar-\(suffix)")

        let recent = try await panel(emptyState: .recent)
        recent.launcher.prepareToShow()
        try await snapshot(recent, "recent-\(suffix)")

        let search = try await panel(emptyState: .none)
        await type("te", in: search)
        try await snapshot(search, "search-\(suffix)")

        let actions = try await panel(emptyState: .recent)
        actions.launcher.prepareToShow()
        actions.launcher.toggleActions()
        try await snapshot(actions, "actions-\(suffix)")

        // Finder's actions, with Force Quit waiting for its second ⏎. Quitting is swapped out: Finder is never quit.
        let confirm = try await panel(emptyState: .recent)
        confirm.launcher.quitApp = { _, _ in }
        confirm.launcher.prepareToShow()
        press(#selector(NSResponder.moveDown(_:)), in: confirm)
        confirm.launcher.toggleActions()
        try #require(confirm.launcher.rows.last == .action(.forceQuit), "Finder isn't running")
        for _ in 1..<confirm.launcher.rows.count { press(#selector(NSResponder.moveDown(_:)), in: confirm) }
        press(#selector(NSResponder.insertNewline(_:)), in: confirm)
        try await snapshot(confirm, "force-quit-\(suffix)")

        // Clear Clipboard History waiting for its second ⏎. Running it is swapped out.
        let clear = try await panel(emptyState: .none)
        clear.launcher.runCommand = { _ in }
        await type("clear clip", in: clear)
        press(#selector(NSResponder.insertNewline(_:)), in: clear)
        try await snapshot(clear, "clear-clipboard-\(suffix)")

        // The problem selected, so the tile shows it.
        let problem = try await panel(emptyState: .recent, problems: ["line 3: unknown setting \"theme\""])
        problem.launcher.prepareToShow()
        press(#selector(NSResponder.moveUp(_:)), in: problem)
        try await snapshot(problem, "problem-\(suffix)")

        // The rows' cuts, then the ⌘K placeholder with the long name in it.
        let long = try await panel(emptyState: .recent, recent: Self.longNames)
        long.launcher.prepareToShow()
        try await snapshot(long, "long-names-\(suffix)")

        let longActions = try await panel(emptyState: .recent, recent: Self.longNames)
        longActions.launcher.prepareToShow()
        longActions.launcher.toggleActions()
        try await snapshot(longActions, "long-actions-\(suffix)")
    }

    /// The clipboard (docs/BRIEF-CLIPBOARD.md): a text from Terminal on the tile, then each other kind selected, a
    /// search with a pin first, the history empty, recording paused, and macOS denying the clipboard.
    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
    func clipboard(appearance: NSAppearance.Name) async throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: appearance)
        defer { NSApp.appearance = nil }
        let suffix = appearance == .darkAqua ? "dark" : "light"
        Self.removeClipboardStores()
        defer { Self.removeClipboardStores() }

        let text = try await clipboardPanel()
        text.launcher.prepareToShow(.clipboard)
        try await snapshot(text, "clipboard-text-\(suffix)")

        for (name, row) in [("link", 1), ("image", 2), ("files", 3)] {
            let panel = try await clipboardPanel()
            panel.launcher.prepareToShow(.clipboard)
            for _ in 0..<row { press(#selector(NSResponder.moveDown(_:)), in: panel) }
            try await snapshot(panel, "clipboard-\(name)-\(suffix)")
        }

        let search = try await clipboardPanel()
        search.launcher.prepareToShow(.clipboard)
        await type("budget", in: search)
        try await snapshot(search, "clipboard-search-\(suffix)")

        let empty = try await clipboardPanel(clips: [])
        empty.launcher.prepareToShow(.clipboard)
        try await snapshot(empty, "clipboard-empty-\(suffix)")

        let paused = try await clipboardPanel()
        paused.launcher.clipboardNotices = [.paused]
        paused.launcher.prepareToShow(.clipboard)
        press(#selector(NSResponder.moveUp(_:)), in: paused)
        try await snapshot(paused, "clipboard-paused-\(suffix)")

        let denied = try await clipboardPanel()
        denied.launcher.clipboardNotices = [.cannotRead]
        denied.launcher.prepareToShow(.clipboard)
        press(#selector(NSResponder.moveUp(_:)), in: denied)
        try await snapshot(denied, "clipboard-cannot-read-\(suffix)")

        // No Accessibility access: ⏎ copies, and the notice says why.
        let noPaste = try await clipboardPanel()
        noPaste.launcher.canPaste = false
        noPaste.launcher.clipboardNotices = [.needsAccessibility]
        noPaste.launcher.prepareToShow(.clipboard)
        press(#selector(NSResponder.moveUp(_:)), in: noPaste)
        try await snapshot(noPaste, "clipboard-accessibility-\(suffix)")

        // ⌘K on the pinned agenda, then Delete waiting for its second ⏎.
        let actions = try await clipboardPanel()
        actions.launcher.prepareToShow(.clipboard)
        for _ in 0..<4 { press(#selector(NSResponder.moveDown(_:)), in: actions) }
        actions.launcher.toggleActions()
        try await snapshot(actions, "clipboard-actions-\(suffix)")
        for _ in 1..<actions.launcher.rows.count { press(#selector(NSResponder.moveDown(_:)), in: actions) }
        try #require(actions.launcher.rows.last == .clipAction(.delete))
        press(#selector(NSResponder.insertNewline(_:)), in: actions)
        try await snapshot(actions, "clipboard-delete-pinned-\(suffix)")
    }

    /// A made-up clipboard history, oldest first: a file from Finder, a pinned agenda from Notes, a screenshot, a link
    /// from Safari, and a config snippet from Terminal, copied two minutes before the fixed clock.
    private func clipboardPanel(
        clips: [(content: ClipContent, source: String?, minutesAgo: Double)]? = nil
    ) async throws -> LauncherPanel {
        let panel = try await panel(emptyState: .none)
        let now = panel.launcher.now()
        let folder = FileManager.default.temporaryDirectory.appending(path: "PithSnapshots-clipboard-\(UUID())")
        let store = ClipboardStore(folder: folder)
        let report = NSHomeDirectory() + "/Documents/Acme/Quarterly_Budget_Review.pdf"
        let agenda = "Agenda for Thursday\nBudget review, then hiring and the launch dates.\n"
        let yaml = """
            services:
              web:
                image: acme/site:2.4
                ports:
                  - "8080:80"
                environment:
                  - API_URL=https://api.acme.example
                  - LOG_LEVEL=info
              worker:
                image: acme/jobs:2.4

            """
        let history =
            try clips ?? [
                (
                    ClipContent(
                        kind: .files, text: report,
                        items: [[representation("public.file-url", URL(filePath: report).dataRepresentation)]]),
                    "com.apple.finder", 190
                ),
                (
                    ClipContent(
                        kind: .richText, text: agenda,
                        items: [
                            [
                                representation("public.html", Data("<b>Agenda for Thursday</b>".utf8)),
                                representation("public.utf8-plain-text", Data(agenda.utf8)),
                            ]
                        ]), "com.apple.Notes", 26 * 60
                ),
                (ClipContent(kind: .image, text: "", items: [], image: try screenshot()), nil, 47),
                (
                    ClipContent(
                        kind: .link, text: "https://github.com/acme/site/pull/42",
                        items: [
                            [
                                representation(
                                    "public.utf8-plain-text", Data("https://github.com/acme/site/pull/42".utf8))
                            ]
                        ]), "com.apple.Safari", 12
                ),
                (
                    ClipContent(
                        kind: .text, text: yaml, items: [[representation("public.utf8-plain-text", Data(yaml.utf8))]]),
                    "com.apple.Terminal", 2
                ),
            ]
        for clip in history.sorted(by: { $0.minutesAgo > $1.minutesAgo }) {
            let stored = try await store.add(clip.content, from: clip.source, at: now - clip.minutesAgo * 60)
            // The agenda is pinned, to show the pin.
            if clip.source == "com.apple.Notes" { try await store.setPinned(true, for: stored.id) }
        }
        let clipboard = ClipboardHistory(store: store)
        await clipboard.load()
        panel.launcher.clipboard = clipboard
        panel.launcher.deliverClip = { _, _ in }
        panel.launcher.canPaste = true
        // The made-up file is there, 2.1 MB.
        panel.launcher.fileFacts = { _ in (true, 2_143_000) }
        return panel
    }

    /// The made-up histories live in the temporary folder, one per panel: each run clears them away.
    private static func removeClipboardStores() {
        let temporary = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temporary.path)) ?? []
        for name in names where name.hasPrefix("PithSnapshots-clipboard-") {
            try? FileManager.default.removeItem(at: temporary.appending(path: name))
        }
    }

    private func representation(_ type: String, _ data: Data) -> Representation {
        Representation(type: type, data: data)
    }

    /// A made-up 1600 × 1000 screenshot: a window with a sidebar and a budget chart.
    private func screenshot() throws -> Data {
        let width = 1600
        let height = 1000
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        func fill(_ rect: CGRect, _ red: Double, _ green: Double, _ blue: Double) {
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(rect)
        }
        fill(CGRect(x: 0, y: 0, width: width, height: height), 0.98, 0.98, 0.97)
        fill(CGRect(x: 0, y: 920, width: width, height: 80), 0.92, 0.92, 0.91)
        fill(CGRect(x: 0, y: 0, width: 320, height: 920), 0.95, 0.95, 0.94)
        for (offset, color) in [(0, (1.0, 0.37, 0.34)), (1, (1.0, 0.74, 0.18)), (2, (0.16, 0.79, 0.25))] {
            context.setFillColor(CGColor(srgbRed: color.0, green: color.1, blue: color.2, alpha: 1))
            context.fillEllipse(in: CGRect(x: 32 + offset * 40, y: 946, width: 26, height: 26))
        }
        for row in 0..<6 {
            fill(CGRect(x: 40, y: 820 - row * 70, width: 200 - row % 3 * 40, height: 22), 0.80, 0.80, 0.79)
        }
        let bars = [0.52, 0.71, 0.63, 0.88, 0.47, 0.76]
        for (index, share) in bars.enumerated() {
            let x = 420 + index * 180
            fill(CGRect(x: x, y: 120, width: 110, height: Int(640 * share)), 0.27, 0.45, 0.78)
        }
        fill(CGRect(x: 400, y: 116, width: 1120, height: 4), 0.70, 0.70, 0.69)
        fill(CGRect(x: 420, y: 820, width: 520, height: 40), 0.25, 0.25, 0.24)
        let image = try #require(context.makeImage())
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }

    /// Like `makePanel`, with `recent` as the history at a fixed time: the newest opened at 14:05 on the day the clock
    /// says, each older one 7 minutes before, so the tile's "opened today at 14:05" never changes.
    private func panel(
        emptyState: Config.EmptyState, problems: [String] = [], recent: [Item] = Self.recent
    ) async throws -> LauncherPanel {
        _ = NSApplication.shared
        let now = try #require(
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 14, minute: 30)))
        let history = HistoryStore(
            file: FileManager.default.temporaryDirectory.appending(path: "PithSnapshots-history.json"))
        for (age, item) in recent.enumerated().reversed() {
            history.record(item.id, at: now.addingTimeInterval(TimeInterval(-25 - 7 * age) * 60))
        }
        let launcher = LauncherViewController(history: history, running: RunningApps(), files: FileSearchEngine())
        launcher.now = { now }
        launcher.emptyState = emptyState
        launcher.problems = problems
        let panel = LauncherPanel(launcher: launcher)
        launcher.index = SearchIndex(items: Self.apps + Command.allCases.map(Item.init(command:)))
        return panel
    }

    /// Waits for the rows' icons, then draws the whole window, background included, at 2× into a PNG.
    private func snapshot(_ panel: LauncherPanel, _ name: String) async throws {
        // Laying out creates the rows on screen, whose cells ask for the icons they're missing.
        panel.layoutIfNeeded()
        for _ in 0..<200 where !iconsReady(panel) || panel.launcher.isResolvingApps {
            try await Task.sleep(for: .milliseconds(25))
            panel.layoutIfNeeded()
        }
        #expect(iconsReady(panel), "\(name): icons still missing")
        panel.displayIfNeeded()
        // The frame view, which draws the window's background under the content.
        let view = try #require(panel.contentView?.superview)
        let scale: CGFloat = 2
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
                pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try #require(bitmap.retagging(with: .sRGB)?.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try png.write(to: Self.folder.appending(path: "\(name).png"))
    }

    /// Every row on screen has its icon, and so does the tile (and there are rows, if the list isn't empty).
    private func iconsReady(_ panel: LauncherPanel) -> Bool {
        var cells = 0
        var ready = panel.launcher.stage.isHidden || panel.launcher.stage.isReady
        panel.launcher.tableView.enumerateAvailableRowViews { rowView, _ in
            cells += 1
            if (rowView.view(atColumn: 0) as? ResultCell)?.icon.image == nil { ready = false }
        }
        return ready && (cells > 0 || panel.launcher.rows.isEmpty)
    }
}
