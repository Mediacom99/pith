import AppKit
import LauncherCore

// MARK: The rows

extension LauncherViewController {
    /// Sets up a cell for `row`: called for new cells, and for the cells on screen when their rows change.
    func configure(_ cell: ResultCell, for row: Row) {
        cell.openKey = openSymbol
        var detail = ""
        var tag = ""
        var isPinned = false
        var cutsAtTheEnd = false
        var isQuietTitle = false
        var corner: CGFloat = 0
        var isDanger = false
        switch row {
        case .item(let item):
            cell.title = item.name
            switch item.kind {
            case .app(let url):
                cell.icon.image = icons.icon(for: url)
                if running.isRunning(item.id) { tag = "running" }
            case .file(let url), .folder(let url):
                cell.icon.image = icons.icon(forFile: url)
                detail = Self.folder(of: url)
            case .command(let command):
                isDanger = command == .clearClipboard && confirming
                if isDanger { cell.title = Self.clearConfirmation }
                cell.icon.image = icons.symbol(Symbols.command(command), tint: isDanger ? .danger : .quiet)
            }
        case .action(let action):
            if case .actions(let item) = sublist {
                isDanger = action == .forceQuit && confirming
                cell.title = isDanger ? Action.forceQuitConfirmation(for: item) : action.title(for: item)
            }
            cell.icon.image = icons.symbol(action.symbol, tint: isDanger ? .danger : .quiet)
            tag = shortcut(for: row) ?? ""
        case .problem(let message):
            cell.title = "Config problem, \(message)"
            cell.icon.image = icons.symbol(Symbols.problem, tint: .warning)
        case .clip(let clip):
            let title = ClipText.title(of: clip, query: searchField.stringValue)
            cell.title = title.text
            isQuietTitle = title.isQuiet
            cutsAtTheEnd = clip.kind == .text || clip.kind == .richText
            detail = ClipText.detail(of: clip)
            tag = ClipText.age(clip.copied, now: now())
            isPinned = clip.pinned
            switch clip.kind {
            case .image:
                cell.icon.image = clipboard.flatMap { clipImages.row(clip, store: $0.store) }
                corner = 4
            case .files:
                cell.icon.image = icons.icon(forFile: URL(filePath: ClipText.firstPath(of: clip)))
            case .text, .richText, .link:
                cell.icon.image = sourceIcon(of: clip, size: .row)
            }
        case .notice(let notice):
            cell.title = Self.noticeTitle(notice)
            cell.icon.image =
                notice == .paused ? icons.symbol(Symbols.paused) : icons.symbol(Symbols.problem, tint: .warning)
        case .clipAction(let action):
            if case .clipActions(let clip) = sublist {
                isDanger = action == .delete && confirming
                cell.title =
                    isDanger ? ClipAction.deleteConfirmation(pinned: clip.pinned) : title(of: action, for: clip)
            }
            cell.icon.image = icons.symbol(action.symbol, tint: isDanger ? .danger : .quiet)
            tag = shortcut(for: row) ?? ""
        }
        cell.detail = detail
        cell.trailingTag = tag
        cell.isPinned = isPinned
        cell.cutsAtTheEnd = cutsAtTheEnd
        cell.isQuietTitle = isQuietTitle
        cell.icon.cornerRadius = corner
        cell.isDanger = isDanger
    }

    /// The folder `url` is in, from the home folder as `~`.
    static func folder(of url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }
}

extension LauncherViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ResultCell.identifier, owner: nil) as? ResultCell ?? ResultCell()
        configure(cell, for: tableRows[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView.makeView(withIdentifier: ResultRowView.identifier, owner: nil) as? ResultRowView ?? ResultRowView()
    }

    /// A click on another row also cancels a Force Quit waiting for its second ⏎, and the tile and Quick Look follow
    /// it, as they follow the keys (`select(row:)`).
    func tableViewSelectionDidChange(_ notification: Notification) {
        cancelConfirmation()
        guard !isSelecting else { return }
        previewSelectionChanged(byUser: true)
        updateTile()
    }

    /// A click on the empty space below the rows keeps the selection, so ⏎ and ⌘K always have a row.
    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        proposed.isEmpty && !rows.isEmpty ? tableView.selectedRowIndexes : proposed
    }
}
