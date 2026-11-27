import AppKit
import LauncherCore

// MARK: The tile

extension LauncherViewController {

    /// The field's placeholder: the item a sublist is for is on the tile, so it only says what you're filtering.
    func placeholder(for sublist: Sublist?) -> String {
        switch sublist {
        case .actions?, .clipActions?: "Filter actions"
        case .openWith?: "Filter apps"
        case nil: mode == .clipboard ? "Search clipboard" : "Search"
        }
    }

    /// Shows what ⏎ acts on: the selected row, or in ⌘K the item the list is for, with the selected action or app as
    /// the primary key.
    func updateTile() {
        if rows.isEmpty, showsEmptyClipboard {
            tile.content = TileView.Content(
                icon: icons.symbol(Symbols.clipboard, size: .tile), name: "Nothing copied yet",
                place: "Copy text, a link, an image or a file and it shows up here", kind: emptyClipboardKeys,
                primary: "")
            return
        }
        guard rows.indices.contains(tableView.selectedRow) else { return }
        let row = rows[tableView.selectedRow]
        let back = TileView.Key(words: "Back", caps: backCaps)
        switch sublist {
        case .actions(let item)?:
            var content = tileContent(for: item)
            guard case .action(let action) = row else { return }
            if action == .forceQuit, confirming {
                content.primary = action.title(for: item)
                content.isDanger = true
                content.secondary = TileView.Key(words: "Cancel", caps: backCaps)
            } else {
                content.primary = action.title(for: item)
                content.secondary = back
            }
            tile.content = content
        case .openWith(let file, _)?:
            var content = tileContent(for: file)
            guard case .item(let app) = row else { return }
            content.primary = "Open in \(app.name)"
            content.secondary = back
            tile.content = content
        case .clipActions(let clip)?:
            var content = tileContent(for: clip)
            guard case .clipAction(let action) = row else { return }
            content.primary = title(of: action, for: clip)
            content.secondary = back
            if action == .delete, confirming {
                content.isDanger = true
                content.secondary = TileView.Key(words: "Cancel", caps: backCaps)
            }
            tile.content = content
        case nil:
            switch row {
            case .item(let item):
                var content = tileContent(for: item)
                if confirming {
                    content.isDanger = true
                    content.secondary = TileView.Key(words: "Cancel", caps: backCaps)
                }
                tile.content = content
            case .problem(let message):
                let (title, detail) = Self.problemTile(message)
                tile.content = TileView.Content(
                    icon: icons.symbol(Symbols.problem, tint: .warning, size: .tile), name: title, place: detail,
                    kind: (ConfigStore.file.path as NSString).abbreviatingWithTildeInPath, primary: "Open Config")
            case .clip(let clip):
                tile.content = tileContent(for: clip)
            case .notice(let notice):
                tile.content = Self.noticeTile(
                    notice,
                    icon: notice == .paused
                        ? icons.symbol(Symbols.paused, size: .tile)
                        : icons.symbol(Symbols.problem, tint: .warning, size: .tile))
            case .action, .clipAction:
                break
            }
        }
    }

    /// The empty clipboard's line about the keys that will act on a clip, as they're configured: "↩ pastes the one you
    /// pick · ⌘K shows its actions · ⌃⌥V pastes the last one, then the one before". A key that's off isn't named.
    var emptyClipboardKeys: String {
        var parts: [String] = []
        if let open = keys[.open].first {
            parts.append("\(open.symbols) \(canPaste ? "pastes" : "copies") the one you pick")
        }
        if let actions = keys[.actions].first { parts.append("\(actions.symbols) shows its actions") }
        if let pasteNextHotkey { parts.append("\(pasteNextHotkey) pastes the last one, then the one before") }
        return parts.joined(separator: " · ")
    }

    /// "Actions ⌘K" on the tile, as `actions` is configured; none when it's off.
    var actionsKey: TileView.Key? {
        keys[.actions].first.map { TileView.Key(words: "Actions", caps: $0.caps) }
    }

    /// ⎋'s key caps, as `back` is configured.
    private var backCaps: [String] { keys[.back].first?.caps ?? [] }

    /// A config problem on the tile: "line 3: unknown setting "theme"" becomes "Config problem, line 3" over
    /// "Unknown setting "theme"". A message that starts with a setting's name keeps its case.
    static func problemTile(_ message: String) -> (title: String, detail: String) {
        guard message.hasPrefix("line "), let colon = message.range(of: ": ") else {
            return ("Config problem", message)
        }
        var detail = String(message[colon.upperBound...])
        if let word = detail.split(separator: " ").first, word.allSatisfy(\.isLetter) {
            detail = detail.prefix(1).uppercased() + detail.dropFirst()
        }
        return ("Config problem, \(message[..<colon.lowerBound])", detail)
    }

    /// An item on the tile: its icon, name, folder, kind, and when it was last opened (or that it's running).
    func tileContent(for item: Item) -> TileView.Content {
        let actions = actionsKey
        let opened = history.history.lastOpened(item.id).map { Self.opened($0, now: now()) }
        func kind(_ parts: String?...) -> String { parts.compactMap { $0 }.joined(separator: " · ") }
        switch item.kind {
        case .app(let url):
            let isRunning = running.isRunning(item.id)
            return TileView.Content(
                icon: icons.icon(for: url, size: .tile), name: item.name, place: Self.folder(of: url),
                kind: kind("Application", isRunning ? "running" : opened), primary: "Open", secondary: actions)
        case .file(let url), .folder(let url):
            return TileView.Content(
                icon: icons.icon(forFile: url, size: .tile), name: item.name, place: Self.folder(of: url),
                kind: kind(icons.typeName(forFile: url), opened), primary: Action.open.title(for: item),
                secondary: actions)
        case .settingsPage(let url):
            return TileView.Content(
                icon: icons.icon(for: url, size: .tile), name: item.name, place: Self.systemSettings,
                kind: kind("Settings page", opened), primary: "Open")
        case .command(.clipboard):
            return TileView.Content(
                icon: icons.symbol(Symbols.command(.clipboard), size: .tile), name: item.name, place: "Pith command",
                kind: clipboardHotkey.map { "Also \($0), from any app" } ?? "", primary: "Open")
        case .command(.installUpdate):
            return TileView.Content(
                icon: icons.symbol(Symbols.command(.installUpdate), size: .tile), name: item.name,
                place: "Pith \(readyUpdate ?? "") is ready", kind: "Pith restarts into it", primary: "Restart")
        case .command(.checkForUpdates):
            return TileView.Content(
                icon: icons.symbol(Symbols.command(.checkForUpdates), size: .tile), name: item.name,
                place: "Pith command", kind: version.map { "Pith \($0)" } ?? "", primary: "Check")
        case .command(.clearClipboard):
            return TileView.Content(
                icon: icons.symbol(Symbols.command(.clearClipboard), size: .tile), name: item.name,
                place: "Pith command", kind: "Pinned items stay", primary: "Clear")
        case .command(let command):
            return TileView.Content(
                icon: icons.symbol(Symbols.command(command), size: .tile), name: item.name, place: "Pith command",
                kind: command == .quit ? version.map { "Pith \($0)" } ?? "" : "", primary: "Run")
        }
    }

    /// Where a settings page is, on its row and tile.
    static let systemSettings = "System Settings"

    /// "opened today at 14:05", "opened yesterday", "opened Tuesday" within the week, else "opened Nov 3".
    static func opened(_ date: Date, now: Date = .now) -> String {
        "opened " + DateWords.day(of: date, now: now)
    }
}
