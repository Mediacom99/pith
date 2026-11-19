import AppKit
import LauncherCore

/// One line in the list.
enum Row: Equatable {
    case item(Item)
    /// A ⌘K action for the app in `LauncherViewController.actionsTarget`.
    case action(AppAction)
    /// Something wrong in config.toml; ⏎ opens the file.
    case problem(String)
}

/// The search field and the list under it: the empty state before you type, search results while you do, and an
/// app's ⌘K actions.
///
/// Searching runs synchronously on the main thread: the index holds a few hundred entries and a search takes
/// microseconds (`make bench`). Everything is laid out with fixed frames, pinned to the top: the panel is only the
/// search bar while there's nothing to list, then grows downward.
final class LauncherViewController: NSViewController {
    var index = SearchIndex.empty {
        didSet {
            boosts = history.history.boosts(for: index)
            loadIcons()
            refresh()
        }
    }

    var emptyState = Config.EmptyState.recent
    /// Shown at the top of the empty state until they're fixed.
    var problems: [String] = []
    /// Runs a launcher command (Open Config, Quit Launcher…).
    var runCommand: (Command) -> Void = { _ in }

    private static let resultLimit = 50
    private static let recentLimit = Int(Layout.visibleRows)

    let searchField = NSTextField()
    let tableView = NSTableView()
    private let separator = NSBox()
    private let scrollView = NSScrollView()
    private let icons = IconStore()
    private let history: HistoryStore
    private let running: RunningApps
    /// The learned ranking, per index item. Recomputed on every show, since it fades with time.
    private var boosts: [Int32] = []
    private(set) var rows: [Row] = []
    /// While ⌘K actions are listed: the app, and the search to go back to.
    private var actionsTarget: (item: Item, query: String, selection: Int)?

    private var panel: LauncherPanel? { viewIfLoaded?.window as? LauncherPanel }

    init(history: HistoryStore, running: RunningApps) {
        self.history = history
        self.running = running
        super.init(nibName: nil, bundle: nil)
        icons.onChange = { [weak self] in self?.refreshVisibleRows() }
        running.onChange = { [weak self] membership in self?.runningAppsChanged(membership: membership) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        // Flipped, so y grows downward and everything stays pinned to the top as the panel grows and shrinks.
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.barHeight))
        let barMidY = Layout.barHeight / 2

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
        // The field copies these onto its editor; the rest is switched off in LauncherPanel's editor.
        searchField.isAutomaticTextCompletionEnabled = false
        searchField.allowsWritingTools = false
        searchField.delegate = self
        let fieldHeight = ceil(searchField.intrinsicContentSize.height)
        searchField.frame = NSRect(
            x: 52, y: (barMidY - fieldHeight / 2).rounded(), width: Layout.width - 72, height: fieldHeight)

        separator.frame = NSRect(x: 0, y: Layout.barHeight, width: Layout.width, height: 1)
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
        tableView.doubleAction = #selector(activateClickedRow)

        scrollView.frame = NSRect(
            x: 0, y: Layout.barHeight + 1, width: Layout.width, height: Layout.expandedHeight - Layout.barHeight - 1)
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: Layout.resultsInset, left: 0, bottom: Layout.resultsInset, right: 0)

        // The one column spans the table; without this it keeps NSTableColumn's default 100 pt width.
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.sizeLastColumnToFit()

        for subview in [searchIcon, searchField, separator, scrollView] {
            root.addSubview(subview)
        }
        separator.isHidden = true
        scrollView.isHidden = true
        view = root
    }

    // MARK: Showing and hiding

    /// Fills in the empty state, so the panel appears with its final size and content.
    func prepareToShow() {
        boosts = history.history.boosts(for: index)
        refresh()
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    /// Empties the field and the list for next time.
    func reset() {
        actionsTarget = nil
        searchField.placeholderString = "Search"
        setQuery("")
        if !rows.isEmpty { show([], selecting: 0) }
    }

    // MARK: The list

    /// Recomputes the rows for the current state and query, and updates the table only if they changed.
    private func refresh() {
        let query = searchField.stringValue
        let new: [Row]
        var selection = 0
        if let target = actionsTarget {
            new = actions(for: target.item, matching: query)
        } else if query.allSatisfy(\.isWhitespace) {
            (new, selection) = emptyStateRows()
        } else {
            new = index.search(query, limit: Self.resultLimit, boosts: boosts).map { .item(index.items[$0]) }
        }
        // Typing that doesn't change the list leaves it, and the selection, alone.
        guard new != rows else { return }
        show(new, selecting: selection)
    }

    private func emptyStateRows() -> (rows: [Row], selection: Int) {
        let notices = problems.map(Row.problem)
        let items: [Item]
        switch emptyState {
        case .none:
            items = []
        case .recent:
            items = history.history.recent(limit: Self.recentLimit).compactMap { id in
                index.position(of: id).map { index.items[$0] }
            }
        case .running:
            items = running.order.compactMap(runningItem)
        }
        // Like ⌘Tab, the running list starts on the previous app: the first one is the app you're in.
        let skip = emptyState == .running && items.count > 1 ? 1 : 0
        return (notices + items.map(Row.item), notices.count + skip)
    }

    /// The index's item for a running app, or one made up for an app outside the indexed folders.
    private func runningItem(_ id: String) -> Item? {
        if let position = index.position(of: id) { return index.items[position] }
        guard let app = running.application(id), let url = app.bundleURL else { return nil }
        return Item(name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, appAt: url, id: id)
    }

    private func actions(for item: Item, matching query: String) -> [Row] {
        let available = AppAction.available(running: running.isRunning(item.id))
        var matcher = FuzzyMatcher(query: query)
        guard !matcher.isEmpty else { return available.map(Row.action) }
        return
            available
            .compactMap { action in matcher.score(SearchKey(action.title)).map { (action, $0) } }
            .sorted { $0.1 > $1.1 }
            .map { .action($0.0) }
    }

    private func show(_ new: [Row], selecting selection: Int) {
        let wasEmpty = rows.isEmpty
        rows = new
        tableView.reloadData()
        if !rows.isEmpty { select(row: min(selection, rows.count - 1)) }
        // Only the search bar while there's nothing to list.
        if rows.isEmpty != wasEmpty {
            separator.isHidden = rows.isEmpty
            scrollView.isHidden = rows.isEmpty
            panel?.setResultsVisible(!rows.isEmpty)
        }
    }

    private func configure(_ cell: ResultCell, for row: Row) {
        switch row {
        case .item(let item):
            cell.textField?.stringValue = item.name
            switch item.kind {
            case .app(let url):
                cell.icon.image = icons.icon(for: url)
                cell.isRunning = running.isRunning(item.id)
            case .command(let command):
                cell.icon.image = icons.symbol(Symbols.command(command))
                cell.isRunning = false
            }
        case .action(let action):
            cell.textField?.stringValue = action.title
            cell.icon.image = icons.symbol(action.symbol)
            cell.isRunning = false
        case .problem(let message):
            cell.textField?.stringValue = "Config problem, \(message)"
            cell.icon.image = icons.symbol(Symbols.problem)
            cell.isRunning = false
        }
    }

    /// New icons or running states: update the rows on screen without reloading.
    private func refreshVisibleRows() {
        tableView.enumerateAvailableRowViews { rowView, row in
            guard let cell = rowView.view(atColumn: 0) as? ResultCell, rows.indices.contains(row) else { return }
            configure(cell, for: rows[row])
        }
    }

    private func loadIcons() {
        let indexed = index.items.lazy.compactMap(\.url)
        let running = running.order.lazy.compactMap { self.running.application($0)?.bundleURL }
        icons.load(Set(indexed).union(running))
    }

    private func runningAppsChanged(membership: Bool) {
        if membership { loadIcons() }
        if panel?.isVisible == true { refreshVisibleRows() }
    }

    private func moveSelection(by offset: Int) {
        guard !rows.isEmpty else { return }
        select(row: min(max(tableView.selectedRow + offset, 0), rows.count - 1))
    }

    private func select(row: Int) {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func setQuery(_ query: String) {
        searchField.stringValue = query
        searchField.currentEditor()?.selectedRange = NSRange(location: query.utf16.count, length: 0)
    }

    // MARK: ⌘K actions

    /// Lists the selected app's actions, or goes back to the search.
    func toggleActions() {
        if actionsTarget != nil {
            closeActions()
            return
        }
        let selection = tableView.selectedRow
        guard rows.indices.contains(selection), case .item(let item) = rows[selection], item.url != nil else { return }
        actionsTarget = (item, searchField.stringValue, selection)
        searchField.placeholderString = "Actions for \(item.name)"
        setQuery("")
        refresh()
    }

    private func closeActions() {
        guard let target = actionsTarget else { return }
        actionsTarget = nil
        searchField.placeholderString = "Search"
        setQuery(target.query)
        refresh()
        if rows.indices.contains(target.selection) { select(row: target.selection) }
    }

    // MARK: Opening

    @objc private func activateClickedRow() {
        activate(row: tableView.clickedRow)
    }

    private func activate(row: Int) {
        guard rows.indices.contains(row) else { return }
        switch rows[row] {
        case .item(let item):
            open(item)
        case .action(let action):
            if let item = actionsTarget?.item { perform(action, on: item) }
        case .problem:
            panel?.dismiss()
            runCommand(.openConfig)
        }
    }

    private func open(_ item: Item) {
        history.record(item.id)
        panel?.dismiss()
        switch item.kind {
        case .app(let url): openApp(at: url)
        case .command(let command): runCommand(command)
        }
    }

    private func perform(_ action: AppAction, on item: Item) {
        guard let url = item.url else { return }
        switch action {
        case .open:
            open(item)
        case .reveal:
            panel?.dismiss()
            Task {
                await runInBackground(qos: .userInitiated) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        case .quit:
            panel?.dismiss()
            running.application(item.id)?.terminate()
        case .forceQuit:
            panel?.dismiss()
            running.application(item.id)?.forceTerminate()
        }
    }

    /// Launches the app, or brings it to the front if it's running.
    private func openApp(at url: URL) {
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
        let handled = ProcessInfo.processInfo.systemUptime
        refresh()
        if let keyDown = NSApp.currentEvent?.timestamp {
            let updated = ProcessInfo.processInfo.systemUptime
            view.window?.displayIfNeeded()
            Log.latency("keystroke → results drawn", event: keyDown, handled: handled, updated: updated)
        }
    }

    /// All keyboard navigation goes through here: the field editor turns keys into commands (and leaves them to the
    /// input method while it's composing).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)): activate(row: tableView.selectedRow)
        case #selector(NSResponder.cancelOperation(_:)):
            if actionsTarget != nil { closeActions() } else { panel?.dismiss() }
        default: return false
        }
        return true
    }
}

extension LauncherViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ResultCell.identifier, owner: nil) as? ResultCell ?? ResultCell()
        configure(cell, for: rows[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView.makeView(withIdentifier: ResultRowView.identifier, owner: nil) as? ResultRowView ?? ResultRowView()
    }
}

/// A view whose y axis grows downward, so subviews with default autoresizing stay pinned to the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
