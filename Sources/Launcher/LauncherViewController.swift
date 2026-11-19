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
/// item's ⌘K actions.
///
/// Each keystroke searches the apps synchronously (a few hundred entries, microseconds) and the files on the file
/// engine's queue (tens of thousands, spread over the cores, well under a millisecond), then shows both merged in one
/// update. The main thread never waits for the files: a newer keystroke makes an older search's results moot.
/// Everything is laid out with fixed frames, pinned to the top: the panel is only the search bar while there's nothing
/// to list, then grows downward.
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
    /// Added to app scores when merging with files (decision 19): about one and a half well-placed characters, so
    /// "saf" gives Safari before safari-notes.md, while a clearly better or habitual file still wins.
    private static let appHeadStart: Int32 = 24

    let searchField = NSTextField()
    let tableView = NSTableView()
    private let separator = NSBox()
    private let scrollView = NSScrollView()
    private let icons = IconStore()
    private let history: HistoryStore
    private let running: RunningApps
    private let files: FileSearchEngine
    /// Bumped by every refresh; a file search whose generation is older is dropped.
    private var searchGeneration = 0
    /// The search in flight, if any: tests await it.
    private(set) var pendingSearch: Task<Void, Never>?
    /// The learned ranking, per index item. Recomputed on every show, since it fades with time.
    private var boosts: [Int32] = []
    /// What the list shows. Empty while the panel is just the search bar.
    private(set) var rows: [Row] = []
    /// What the table holds: `rows`, or the last non-empty rows while the list is hidden. Keeping them means the
    /// table keeps its cells, which the next results reconfigure in place instead of building new ones.
    private var tableRows: [Row] = []
    /// While ⌘K actions are listed: the item, and the search to go back to, as it was.
    private var actionsTarget: (item: Item, query: String, rows: [Row], selection: Int)?

    private var panel: LauncherPanel? { viewIfLoaded?.window as? LauncherPanel }

    init(history: HistoryStore, running: RunningApps, files: FileSearchEngine) {
        self.history = history
        self.running = running
        self.files = files
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
        // Catches an app that quit without us noticing, so no row shows a stale running dot.
        if running.sync() { loadIcons() }
        boosts = history.history.boosts(for: index)
        files.setBoosts(history.history.fileBoosts())
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

    /// Recomputes the rows for the current state and query, and updates the table only if they changed. With a
    /// query, the files arrive asynchronously and the update happens then. `keystroke` (the key press time and when
    /// handling it started) is for the latency log.
    private func refresh(keystroke: (event: TimeInterval, handled: TimeInterval)? = nil) {
        searchGeneration += 1
        let generation = searchGeneration
        let query = searchField.stringValue
        if let target = actionsTarget {
            update(actions(for: target.item, matching: query), selecting: 0, keystroke: keystroke)
        } else if query.allSatisfy(\.isWhitespace) {
            let (rows, selection) = emptyStateRows()
            update(rows, selecting: selection, keystroke: keystroke)
        } else {
            let apps = index.scoredSearch(query, limit: Self.resultLimit, boosts: boosts)
            pendingSearch = Task {
                guard let hits = await files.search(query, limit: Self.resultLimit, generation: generation),
                    generation == searchGeneration
                else { return }
                update(merge(apps: apps, files: hits), selecting: 0, keystroke: keystroke)
            }
        }
    }

    /// Typing that doesn't change the list leaves it, and the selection, alone.
    private func update(
        _ new: [Row], selecting selection: Int, keystroke: (event: TimeInterval, handled: TimeInterval)?
    ) {
        if new != rows { show(new, selecting: selection) }
        if let keystroke {
            let updated = ProcessInfo.processInfo.systemUptime
            view.window?.displayIfNeeded()
            Log.latency(
                "keystroke → results drawn", event: keystroke.event, handled: keystroke.handled, updated: updated)
        }
    }

    /// One list, best first (decision 19). Apps found by the file index too (in ~/Applications) appear once.
    private func merge(apps: [(index: Int, score: Int32)], files hits: [FileHit]) -> [Row] {
        var scored = apps.map { (item: index.items[$0.index], score: $0.score + Self.appHeadStart) }
        for hit in hits where index.position(of: hit.path) == nil {
            scored.append((Item(path: hit.path, isFolder: hit.isFolder), hit.score))
        }
        // Stable: equal scores keep apps first, then each source's own order.
        let ranked = scored.enumerated().sorted { a, b in
            a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
        }
        return ranked.prefix(Self.resultLimit).map { .item($0.element.item) }
    }

    private func emptyStateRows() -> (rows: [Row], selection: Int) {
        let notices = problems.map(Row.problem)
        let items: [Item]
        switch emptyState {
        case .none:
            items = []
        case .recent:
            items = history.history.recent(limit: Self.recentLimit).compactMap { id in
                Item(fileID: id) ?? index.position(of: id).map { index.items[$0] }
            }
        case .running:
            // Open apps first, then every other app alphabetically (the index is sorted by name).
            let open = running.order.compactMap(runningItem)
            let others = index.items.filter { $0.isApp && !running.isRunning($0.id) }
            items = open + others
        }
        // Like ⌘Tab, the running list starts on the previous app: the first one is the app you're in.
        let skip = emptyState == .running && running.order.count > 1 ? 1 : 0
        return (notices + items.map(Row.item), notices.count + skip)
    }

    /// The index's item for a running app, or one made up for an app outside the indexed folders.
    private func runningItem(_ id: String) -> Item? {
        if let position = index.position(of: id) { return index.items[position] }
        guard let app = running.application(id), let url = app.bundleURL else { return nil }
        return Item(name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, appAt: url, id: id)
    }

    private func actions(for item: Item, matching query: String) -> [Row] {
        let available = AppAction.available(for: item, running: running.isRunning(item.id))
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
        if !rows.isEmpty {
            if tableRows.isEmpty {
                tableRows = rows
                tableView.reloadData()
            } else {
                // reloadData would build fresh cells for every visible row (the old ones are still attached when it
                // asks), so the cells already there get their new rows. Only rows added at the end get new views.
                tableRows = rows
                tableView.noteNumberOfRowsChanged()
                refreshVisibleRows()
            }
            select(row: min(selection, rows.count - 1))
        }
        // Only the search bar while there's nothing to list.
        if rows.isEmpty != wasEmpty {
            separator.isHidden = rows.isEmpty
            scrollView.isHidden = rows.isEmpty
            panel?.setResultsVisible(!rows.isEmpty)
        }
    }

    private func configure(_ cell: ResultCell, for row: Row) {
        var detail = ""
        var isRunning = false
        switch row {
        case .item(let item):
            cell.textField?.stringValue = item.name
            switch item.kind {
            case .app(let url):
                cell.icon.image = icons.icon(for: url)
                isRunning = running.isRunning(item.id)
            case .file(let url), .folder(let url):
                cell.icon.image = icons.icon(forFile: url)
                detail = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            case .command(let command):
                cell.icon.image = icons.symbol(Symbols.command(command))
            }
        case .action(let action):
            cell.textField?.stringValue = action.title
            cell.icon.image = icons.symbol(action.symbol)
        case .problem(let message):
            cell.textField?.stringValue = "Config problem, \(message)"
            cell.icon.image = icons.symbol(Symbols.problem)
        }
        cell.detail = detail
        cell.isRunning = isRunning
        cell.needsLayout = true  // the title's width depends on its text
    }

    /// New icons or running states: update the rows on screen without reloading.
    private func refreshVisibleRows() {
        tableView.enumerateAvailableRowViews { rowView, row in
            guard let cell = rowView.view(atColumn: 0) as? ResultCell, tableRows.indices.contains(row) else { return }
            configure(cell, for: tableRows[row])
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
        actionsTarget = (item, searchField.stringValue, rows, selection)
        searchField.placeholderString = "Actions for \(item.name)"
        setQuery("")
        refresh()
    }

    /// Back to the search as it was: same query, rows and selection, without searching again.
    private func closeActions() {
        guard let target = actionsTarget else { return }
        actionsTarget = nil
        searchGeneration += 1  // a search still in flight would overwrite the restored rows
        searchField.placeholderString = "Search"
        setQuery(target.query)
        show(target.rows, selecting: target.selection)
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
        case .file(let url), .folder(let url): openFile(at: url)
        case .command(let command): runCommand(command)
        }
    }

    /// Opens a file in its default app, a folder in Finder.
    private func openFile(at url: URL) {
        Task {
            do {
                _ = try await NSWorkspace.shared.open(url, configuration: .init())
            } catch {
                Log.app.error(
                    "Couldn't open \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
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
        refresh(keystroke: NSApp.currentEvent.map { ($0.timestamp, handled) })
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
}

/// A view whose y axis grows downward, so subviews with default autoresizing stay pinned to the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
