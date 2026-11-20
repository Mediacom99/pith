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

    /// Like `makePanel`, with `recent` as the history at a fixed time: the newest opened at 14:05 on the day the clock
    /// says, each older one 7 minutes before, so the tile's "opened today at 14:05" never changes.
    private func panel(
        emptyState: Config.EmptyState, problems: [String] = [], recent: [Item] = Self.recent
    ) async throws -> LauncherPanel {
        _ = NSApplication.shared
        let now = try #require(
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 14, minute: 30)))
        let history = HistoryStore(
            file: FileManager.default.temporaryDirectory.appending(path: "LauncherSnapshots-history.json"))
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
        for _ in 0..<200 where !iconsReady(panel) { try await Task.sleep(for: .milliseconds(25)) }
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
        var ready = panel.launcher.stage.isHidden || panel.launcher.stage.icon.image != nil
        panel.launcher.tableView.enumerateAvailableRowViews { rowView, _ in
            cells += 1
            if (rowView.view(atColumn: 0) as? ResultCell)?.icon.image == nil { ready = false }
        }
        return ready && (cells > 0 || panel.launcher.rows.isEmpty)
    }
}
