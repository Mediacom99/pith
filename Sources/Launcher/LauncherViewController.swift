import AppKit
import LauncherCore

/// The search field and the result list.
///
/// Searching runs synchronously on the main thread: the app index holds a few hundred entries and a search takes
/// microseconds (`make bench`). Everything is laid out with fixed frames, since the panel never changes size.
final class LauncherViewController: NSViewController {
    var index = AppIndex.empty {
        didSet {
            icons.load(index.apps.map(\.url)) { [weak self] in self?.refreshVisibleIcons() }
            show(index.search(searchField.stringValue, limit: Self.resultLimit))
        }
    }

    private static let resultLimit = 50

    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let icons = IconStore()
    /// Indices into `index.apps`, best match first.
    private var results: [Int] = []

    private var panel: LauncherPanel? { viewIfLoaded?.window as? LauncherPanel }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
        let barMidY = Layout.height - Layout.barHeight / 2

        let searchIcon = NSImageView(frame: NSRect(x: 20, y: barMidY - 10, width: 20, height: 20))
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        searchIcon.contentTintColor = .secondaryLabelColor

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 22)
        searchField.placeholderString = "Search"
        searchField.cell?.isScrollable = true
        searchField.cell?.wraps = false
        searchField.delegate = self
        let fieldHeight = ceil(searchField.intrinsicContentSize.height)
        searchField.frame = NSRect(
            x: 52, y: (barMidY - fieldHeight / 2).rounded(), width: Layout.width - 72, height: fieldHeight)

        let separator = NSBox(
            frame: NSRect(x: 0, y: Layout.height - Layout.barHeight - 1, width: Layout.width, height: 1))
        separator.boxType = .separator

        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result")))
        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = Layout.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.refusesFirstResponder = true  // typing always goes to the search field
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openClickedRow)

        let scrollView = NSScrollView(
            frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height - Layout.barHeight - 1))
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: Layout.resultsInset, left: 0, bottom: Layout.resultsInset, right: 0)

        for subview in [searchIcon, searchField, separator, scrollView] {
            root.addSubview(subview)
        }
        view = root
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    func reset() {
        searchField.stringValue = ""
        if !results.isEmpty { show([]) }
    }

    private func show(_ found: [Int]) {
        results = found
        tableView.reloadData()
        if !found.isEmpty { select(row: 0) }
    }

    private func refreshVisibleIcons() {
        tableView.enumerateAvailableRowViews { rowView, row in
            guard let cell = rowView.view(atColumn: 0) as? ResultCell, results.indices.contains(row) else { return }
            cell.icon.image = icons.icon(for: index.apps[results[row]].url)
        }
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        select(row: min(max(tableView.selectedRow + offset, 0), results.count - 1))
    }

    private func select(row: Int) {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    @objc private func openClickedRow() {
        open(row: tableView.clickedRow)
    }

    /// Launches the app, or brings it to the front if it's running.
    private func open(row: Int) {
        guard results.indices.contains(row) else { return }
        let url = index.apps[results[row]].url
        panel?.dismiss()
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            } catch {
                Log.app.error(
                    "Couldn't open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension LauncherViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        let found = index.search(searchField.stringValue, limit: Self.resultLimit)
        // Typing that doesn't change the matches leaves the list, and the selection, alone.
        if found != results { show(found) }
        if let keyDown = NSApp.currentEvent?.timestamp {
            view.window?.displayIfNeeded()
            Log.latency("keystroke → results drawn", since: keyDown)
        }
    }

    /// All keyboard navigation goes through here: the field editor turns keys into commands (and leaves them to the
    /// input method while it's composing).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)): open(row: tableView.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)): panel?.dismiss()
        default: return false
        }
        return true
    }
}

extension LauncherViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ResultCell.identifier, owner: nil) as? ResultCell ?? ResultCell()
        let app = index.apps[results[row]]
        cell.textField?.stringValue = app.name
        cell.icon.image = icons.icon(for: app.url)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView.makeView(withIdentifier: ResultRowView.identifier, owner: nil) as? ResultRowView ?? ResultRowView()
    }
}
