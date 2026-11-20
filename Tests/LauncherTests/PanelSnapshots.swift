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

        let problem = try await panel(emptyState: .recent, problems: ["line 3: unknown setting theme"])
        problem.launcher.prepareToShow()
        try await snapshot(problem, "problem-\(suffix)")
    }

    /// Like `makePanel`, with `recent` as the history: each open a moment after the last, so their order is fixed.
    private func panel(emptyState: Config.EmptyState, problems: [String] = []) async throws -> LauncherPanel {
        _ = NSApplication.shared
        let history = HistoryStore(
            file: FileManager.default.temporaryDirectory.appending(path: "LauncherSnapshots-history.json"))
        for item in Self.recent.reversed() {
            history.record(item.id)
            try await Task.sleep(for: .milliseconds(1))
        }
        let launcher = LauncherViewController(history: history, running: RunningApps(), files: FileSearchEngine())
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

    /// Every row on screen has its icon (and there are rows, if the list isn't empty).
    private func iconsReady(_ panel: LauncherPanel) -> Bool {
        var cells = 0
        var ready = true
        panel.launcher.tableView.enumerateAvailableRowViews { rowView, _ in
            cells += 1
            if (rowView.view(atColumn: 0) as? ResultCell)?.icon.image == nil { ready = false }
        }
        return ready && (cells > 0 || panel.launcher.rows.isEmpty)
    }
}
