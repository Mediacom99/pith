import AppKit
import LauncherCore

/// The search field, the tile under it and the list under that: the empty state before you type, search results while
/// you do, and an item's ⌘K actions. The tile shows what ⏎ acts on and the keys for it (decision 29).
///
/// Each keystroke searches the apps synchronously (a few hundred entries, microseconds) and the files on the file
/// engine's queue (tens of thousands, spread over the cores, well under a millisecond), then shows both merged in one
/// update. The main thread never waits for the files: a newer keystroke makes an older search's results moot.
/// Everything is laid out with fixed frames, pinned to the top: the panel is only the search bar while there's nothing
/// to list, then grows downward.
///
/// This file has its state, the list and the selection; each other concern is an extension in its own
/// `LauncherViewController+….swift` (the tile, the rows, ⌘K and opening, the clipboard, keys, Quick Look). The state
/// they share is internal rather than private, since Swift's `private` ends at the file.
final class LauncherViewController: NSViewController {
    /// What the panel searches: apps, files and commands, or the clipboard history (decision 34, docs/BRIEF-CLIPBOARD.md).
    enum Mode {
        case launcher, clipboard
    }

    var index = SearchIndex.empty {
        didSet {
            index.setAliases([clipboardAlias], for: .clipboard)
            boosts = history.history.boosts(for: index)
            loadIcons()
            refresh()
        }
    }

    var emptyState = Config.EmptyState.recent
    /// Shown at the top of the empty state until they're fixed.
    var problems: [String] = []
    /// Runs a launcher command (Open Config, Quit Pith…).
    var runCommand: (Command) -> Void = { _ in }
    /// Commands that don't apply now, left out of the results and the recent list: Resume Clipboard Recording while
    /// recording, Pause while paused (decision 45).
    var hiddenCommands: Set<Command> = [.resumeClipboard]
    /// `[open_with]`, resolved: extension or type → app.
    var openWithApps: [String: URL] = [:]
    /// `[actions] terminal`, resolved.
    var terminalApp: URL?
    /// Runs Zip in the background, and posts its notification and those for failed actions.
    var notifier: Notifier?
    /// Says that an action failed after the panel closed: what failed, the item, and why (decision 32). Tests swap it
    /// out, so they never post a notification.
    lazy var reportFailure: (_ title: String, _ item: URL?, _ reason: String) -> Void = { [weak self] in
        self?.notifier?.failed($0, item: $1, reason: $2)
    }
    /// The time, for "opened today at 14:05". Snapshots fix it.
    var now: () -> Date = { .now }
    /// The clipboard history, and what it says above its clips.
    var clipboard: ClipboardHistory? {
        didSet {
            clipboard?.onChange = { [weak self] in self?.clipboardChanged() }
            clipboardChanged()
        }
    }
    var clipboardNotices: [ClipboardNotice] = [] {
        didSet { if clipboardNotices != oldValue, mode == .clipboard { refresh() } }
    }
    /// Deals with a notice: resumes recording, or opens the setting.
    var resolveNotice: (ClipboardNotice) -> Void = { _ in }
    /// Whether Pith may press ⌘V for you (Accessibility access): ⏎ pastes, or only copies.
    var canPaste = false {
        didSet { if canPaste != oldValue, mode == .clipboard { refresh() } }
    }
    /// Paste next's run (decision 64): the history as it was at its first press, and how far down it is.
    var pasteRun: PasteRun?
    /// The first ⏎ without Accessibility access asks for it.
    var askForAccessibility: () -> Void = {}
    /// Called as the clipboard is shown, to check access again.
    var onShowClipboard: () -> Void = {}
    /// Puts a clip back on the clipboard, and pastes it. Tests swap it out, so they never touch the clipboard or type.
    lazy var deliverClip: (Clip, ClipDelivery) -> Void = { [weak self] in self?.deliver($0, $1) }
    /// Where Save as File puts a clip (decision 39), and the notification that says so. Tests swap both.
    var saveFolder = URL.downloadsDirectory
    lazy var reportSaved: (URL) -> Void = { [weak self] in self?.notifier?.saved($0) }
    /// `[open_links]`, resolved: URL scheme → app (decision 16). Other links open in their default app.
    var openLinks: [String: URL] {
        get { linkApps.configured }
        set { linkApps.configured = newValue }
    }
    /// The clipboard's hotkey as menus show it (`⇧⌘V`), for the Clipboard History command's tile.
    var clipboardHotkey: String?
    /// The version of a downloaded update, ready to install: Update Pith is listed first in the empty state, and
    /// found by search, until then.
    var readyUpdate: String?
    /// Whether this copy updates itself (`Updater.isEnabled`), so Check for Updates does something (decision 50).
    var checksForUpdates = false
    /// Pith's version, on the Quit Pith tile, so whoever tries a build can say which one it is (decision 47).
    var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    /// The keys inside the panel, from `[keys]` (decision 55); the first of each is the one the panel shows.
    var keys = KeyBindings.defaults {
        didSet {
            guard keys != oldValue else { return }
            openSymbol = keys[.open].first?.symbols ?? ""
            tile.openCaps = keys[.open].first?.caps ?? []
            refreshVisibleRows()
            updateTile()
        }
    }
    /// What the selected row ends in, kept so drawing a row doesn't build it.
    private(set) var openSymbol = "↩"
    /// Clipboard History's alias (decision 42), and with a space after it the prefix that opens the clipboard. Empty
    /// for neither (`[launcher] clipboard_alias`).
    var clipboardAlias = "c" {
        didSet { if clipboardAlias != oldValue { index.setAliases([clipboardAlias], for: .clipboard) } }
    }
    /// Whether a copied file is still there, and its size, read on a worker. Snapshots fix them.
    var fileFacts: @Sendable (String) -> FileFacts.Fact {
        get { facts.read }
        set { facts.read = newValue }
    }
    /// Quits or force-quits a running app. Tests swap it out, so they never quit a real one.
    var quitApp: (NSRunningApplication, _ force: Bool) -> Void = { app, force in
        if force { app.forceTerminate() } else { app.terminate() }
    }

    private static let resultLimit = 50
    /// How many clips the clipboard lists: five show, the rest scroll.
    static let clipLimit = 100
    private static let recentLimit = Int(Layout.visibleRows)
    /// Added to app scores when merging with files (decision 19): about one and a half well-placed characters, so
    /// "saf" gives Safari before safari-notes.md, while a clearly better or habitual file still wins.
    private static let appHeadStart: Int32 = 24

    let searchField = NSTextField()
    let tableView = NSTableView()
    let tile = TileView(
        frame: NSRect(
            x: Layout.tileMargin, y: Layout.barHeight + 1 + Layout.tileMargin,
            width: Layout.width - 2 * Layout.tileMargin,
            height: Layout.tileHeight))
    private let separator = NSBox()
    private let scrollView = OverlayScrollView()
    private let searchIcon = NSImageView()
    let icons = IconStore()
    let clipImages = ClipImages()
    /// Whether the clipboard's copied files are still there, and their size.
    let facts = FileFacts()
    /// The app each link scheme opens in, for "Open in Safari".
    let linkApps = LinkApps()
    let paster = ClipPaster()
    private(set) var mode = Mode.launcher
    /// Whether the panel shows more than the search bar.
    private var isExpanded = false
    /// After pinning or deleting, the clip (or the place in the list) to keep selected.
    var keepSelection: (id: Int64, position: Int)?
    /// While `select(row:)` selects, which updates the tile itself; otherwise a selection change is a click.
    var isSelecting = false
    let history: HistoryStore
    let running: RunningApps
    private let files: FileSearchEngine
    /// Bumped by every refresh; a file search whose generation is older is dropped.
    var searchGeneration = 0
    /// The search in flight, if any: tests await it.
    private(set) var pendingSearch: Task<Void, Never>?
    /// The learned ranking, per index item. Recomputed on every show, since it fades with time.
    private var boosts: [Int32] = []
    /// What the list shows. Empty while the panel is just the search bar.
    private(set) var rows: [Row] = []
    /// What the table holds: `rows`, or the last non-empty rows while the list is hidden. Keeping them means the
    /// table keeps its cells, which the next results reconfigure in place instead of building new ones.
    private(set) var tableRows: [Row] = []
    /// The ⌘K list showing, if any.
    var sublist: Sublist?
    /// What ⎋ goes back to, innermost last: each level's sublist (nil for the search), query, rows and selection.
    var backStack: [(sublist: Sublist?, query: String, rows: [Row], selection: Int)] = []
    /// Force Quit, Clear Clipboard History or deleting a pinned clip is waiting for its second ⏎ (decision 28). ⎋,
    /// typing or moving the selection cancels it.
    var confirming = false

    /// The file Quick Look shows: the one it was opened on, until the user moves the selection (`PreviewTarget`).
    /// Quick Look asks for it whenever it likes, so it's never worked out from the selection then: a list refreshed
    /// meanwhile would show another file.
    var previewing: URL?
    /// The key press being handled, and the one that last opened or closed the preview: one press toggles it once,
    /// whatever path it takes to the panel (a key equivalent, then a key).
    var pressing: NSEvent?
    weak var previewToggle: NSEvent?

    var panel: LauncherPanel? { viewIfLoaded?.window as? LauncherPanel }

    init(history: HistoryStore, running: RunningApps, files: FileSearchEngine) {
        self.history = history
        self.running = running
        self.files = files
        super.init(nibName: nil, bundle: nil)
        icons.onChange = { [weak self] in self?.refreshVisibleRows() }
        clipImages.onChange = { [weak self] in self?.refreshVisibleRows() }
        linkApps.onChange = { [weak self] in self?.refreshVisibleRows() }
        facts.onChange = { [weak self] in self?.updateTile() }
        paster.onFailure = { [weak self] title, reason in self?.failed(title, nil, reason: reason) }
        paster.onAccessChecked = { [weak self] allowed in
            self?.canPaste = allowed
            if !allowed { self?.askForAccessibility() }
        }
        running.onChange = { [weak self] membership in self?.runningAppsChanged(membership: membership) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        // Flipped, so y grows downward and everything stays pinned to the top as the panel grows and shrinks.
        let root = PanelView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.barHeight))
        let barMidY = Layout.barHeight / 2

        searchIcon.frame = NSRect(
            x: Layout.iconX + (Layout.iconSize - 20) / 2, y: barMidY - 10, width: 20, height: 20)
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        searchIcon.contentTintColor = Palette.quiet

        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 20)
        searchField.placeholderString = "Search"
        searchField.cell?.isScrollable = true
        searchField.cell?.wraps = false
        // The field copies these onto its editor; the rest is switched off in LauncherPanel's editor.
        searchField.isAutomaticTextCompletionEnabled = false
        searchField.allowsWritingTools = false
        searchField.delegate = self
        let fieldHeight = ceil(searchField.intrinsicContentSize.height)
        searchField.frame = NSRect(
            x: Layout.textX, y: (barMidY - fieldHeight / 2).rounded(),
            width: Layout.width - Layout.textX - Layout.textTrailing - 2, height: fieldHeight)

        separator.frame = NSRect(x: 0, y: Layout.barHeight, width: Layout.width, height: 1)
        separator.boxType = .separator

        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result")))
        tableView.headerView = nil
        // Plain, so the geometry is all ours: the inset style adds padding of its own, which pushed the 8th row out of
        // the panel. ResultRowView draws the inset selection instead.
        tableView.style = .plain
        tableView.rowHeight = Layout.rowHeight
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.refusesFirstResponder = true  // typing always goes to the search field
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(activateClickedRow)

        scrollView.frame = NSRect(
            x: 0, y: Layout.listTop, width: Layout.width, height: Layout.expandedHeight - Layout.listTop)
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: Layout.listBottomInset, right: 0)

        // The one column spans the table; without this it keeps NSTableColumn's default 100 pt width.
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.sizeLastColumnToFit()

        for subview in [searchIcon, searchField, separator, tile, scrollView] {
            root.addSubview(subview)
        }
        separator.isHidden = true
        tile.isHidden = true
        scrollView.isHidden = true
        view = root
    }

    // MARK: Showing and hiding

    /// Fills in the empty state, so the panel appears with its final size and content: the launcher's, or the
    /// clipboard's (⌘⇧V).
    func prepareToShow(_ mode: Mode = .launcher) {
        // Catches an app that quit without us noticing, so no row shows a stale running dot.
        if running.sync() { loadIcons() }
        boosts = history.history.boosts(for: index)
        files.setBoosts(history.history.fileBoosts())
        // A folder refused at its prompt may have been allowed in System Settings since (decision 60).
        files.recheckRefused()
        if mode != self.mode {
            self.mode = mode
            applyMode()
        }
        if mode == .clipboard {
            onShowClipboard()
            facts.markStale()
        }
        refresh()
    }

    /// Switches between the launcher and the clipboard while the panel is showing, from an empty field. The clipboard
    /// checks access again, as it does when ⌘⇧V opens it: it may have been given since.
    func switchMode(to new: Mode) {
        guard new != mode else { return }
        sublist = nil
        backStack = []
        confirming = false
        mode = new
        applyMode()
        setQuery("")
        if new == .clipboard {
            onShowClipboard()
            facts.markStale()
        }
        refresh()
    }

    /// The tile's height, where the list starts, the bar's symbol and its placeholder, for the mode.
    private func applyMode() {
        let clipboard = mode == .clipboard
        tile.frame.size.height = clipboard ? Layout.clipboardTileHeight : Layout.tileHeight
        let top = clipboard ? Layout.clipboardListTop : Layout.listTop
        scrollView.frame = NSRect(x: 0, y: top, width: Layout.width, height: Layout.expandedHeight - top)
        searchIcon.image = NSImage(
            systemSymbolName: clipboard ? Symbols.clipboard : "magnifyingglass", accessibilityDescription: nil)
        searchField.placeholderString = placeholder(for: sublist)
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    /// Empties the field and the list for next time.
    func reset() {
        sublist = nil
        backStack = []
        confirming = false
        if mode != .launcher {
            mode = .launcher
            applyMode()
        }
        searchField.placeholderString = placeholder(for: nil)
        setQuery("")
        if !rows.isEmpty || isExpanded { show([], selecting: 0, byUser: false) }
        icons.trimTypes()
    }

    // MARK: The list

    /// Recomputes the rows for the current state and query, and updates the table only if they changed. With a
    /// query, the files arrive asynchronously and the update happens then. `keystroke` (the key press time and when
    /// handling it started) is for the latency log.
    func refresh(keystroke: (event: TimeInterval, handled: TimeInterval)? = nil) {
        searchGeneration += 1
        let generation = searchGeneration
        let query = searchField.stringValue
        if let sublist {
            update(rows(for: sublist, matching: query), selecting: 0, keystroke: keystroke)
        } else if mode == .clipboard {
            var (rows, selection) = clipRows(matching: query)
            if let keep = keepSelection {
                keepSelection = nil
                selection =
                    rows.firstIndex { if case .clip(let clip) = $0 { clip.id == keep.id } else { false } }
                    ?? min(keep.position, max(0, rows.count - 1))
            }
            update(rows, selecting: selection, keystroke: keystroke)
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
        // Rows that typing brought are the user's doing; others (a copy, the apps changing) aren't (`PreviewTarget`).
        if new != rows || isExpanded != shouldExpand(new) { show(new, selecting: selection, byUser: keystroke != nil) }
        if let keystroke {
            let updated = ProcessInfo.processInfo.systemUptime
            view.window?.displayIfNeeded()
            Log.latency(
                "keystroke → results drawn", event: keystroke.event, handled: keystroke.handled, updated: updated)
        }
    }

    /// One list, best first (decision 19). Apps found by the file index too (in ~/Applications) appear once.
    private func merge(apps: [(index: Int, score: Int32)], files hits: [FileHit]) -> [Row] {
        var scored = apps.compactMap { app in
            let item = index.items[app.index]
            return isHidden(item) ? nil : (item: item, score: app.score + Self.appHeadStart)
        }
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
        // Problems first, then a ready update; the selection starts below them.
        let update = Item(command: .installUpdate)
        let notices = problems.map(Row.problem) + (readyUpdate == nil ? [] : [.item(update)])
        let items: [Item]
        switch emptyState {
        case .none:
            items = []
        case .recent:
            items = history.history.recent(limit: Self.recentLimit).compactMap { id in
                Item(fileID: id) ?? index.position(of: id).map { index.items[$0] }
            }.filter { !isHidden($0) && $0 != update }
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

    private func isHidden(_ item: Item) -> Bool {
        guard case .command(let command) = item.kind else { return false }
        if hiddenCommands.contains(command) { return true }
        return switch command {
        case .installUpdate: readyUpdate == nil
        case .checkForUpdates: !checksForUpdates || readyUpdate != nil
        default: false
        }
    }

    /// The index's item for a running app, or one made up for an app outside the indexed folders.
    private func runningItem(_ id: String) -> Item? {
        if let position = index.position(of: id) { return index.items[position] }
        guard let app = running.application(id), let url = app.bundleURL else { return nil }
        return Item(name: app.localizedName ?? url.deletingPathExtension().lastPathComponent, appAt: url, id: id)
    }

    /// A sublist's rows, filtered by `query` (fuzzy, best first).
    private func rows(for sublist: Sublist, matching query: String) -> [Row] {
        let candidates: [(row: Row, name: String)] =
            switch sublist {
            case .actions(let item):
                Action.available(for: item, running: running.isRunning(item.id)).map {
                    (.action($0), $0.title(for: item))
                }
            case .openWith(_, let apps):
                apps.map { (.item($0), $0.name) }
            case .clipActions(let clip):
                ClipAction.available(for: clip, canPaste: canPaste).map { (.clipAction($0), title(of: $0, for: clip)) }
            }
        var matcher = FuzzyMatcher(query: query)
        guard !matcher.isEmpty else { return candidates.map(\.row) }
        return
            candidates
            .compactMap { candidate in matcher.score(SearchKey(candidate.name)).map { (candidate.row, $0) } }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Rows show the tile, and so does the clipboard with nothing in it yet; otherwise it's only the search bar.
    private func shouldExpand(_ rows: [Row]) -> Bool {
        !rows.isEmpty || showsEmptyClipboard
    }

    var showsEmptyClipboard: Bool {
        mode == .clipboard && sublist == nil && searchField.stringValue.allSatisfy(\.isWhitespace)
            && (clipboard?.index.count ?? 0) == 0 && clipboardNotices.isEmpty
    }

    func show(_ new: [Row], selecting selection: Int, byUser: Bool) {
        rows = new
        if !rows.isEmpty {
            if tableRows.isEmpty {
                tableRows = rows
                tableView.reloadData()
            } else {
                // reloadData would build fresh cells for every visible row (the old ones are still attached when it
                // asks), so the cells already there get their new rows. Only rows added at the end get new views,
                // configured as they're built and shown at once: noteNumberOfRowsChanged would fade them in over
                // ~200 ms.
                let old = tableRows.count
                tableRows = rows
                refreshVisibleRows()
                if rows.count > old {
                    tableView.insertRows(at: IndexSet(old..<rows.count), withAnimation: [])
                } else if rows.count < old {
                    tableView.removeRows(at: IndexSet(rows.count..<old), withAnimation: [])
                }
            }
            select(row: max(0, min(selection, rows.count - 1)), byUser: byUser)
        }
        // Only the search bar while there's nothing to list.
        let expanded = shouldExpand(rows)
        if expanded != isExpanded {
            isExpanded = expanded
            separator.isHidden = !expanded
            tile.isHidden = !expanded
            panel?.setResultsVisible(expanded)
        }
        scrollView.isHidden = rows.isEmpty
        updateTile()
    }

    /// New icons or running states: update the rows on screen, and the tile, without reloading.
    func refreshVisibleRows() {
        tableView.enumerateAvailableRowViews { rowView, row in
            guard let cell = rowView.view(atColumn: 0) as? ResultCell, tableRows.indices.contains(row) else { return }
            configure(cell, for: tableRows[row])
        }
        updateTile()
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

    func moveSelection(by offset: Int) {
        guard !rows.isEmpty else { return }
        select(row: min(max(tableView.selectedRow + offset, 0), rows.count - 1), byUser: true)
    }

    /// Puts a Force Quit that's waiting for its second ⏎ back to normal.
    func cancelConfirmation() {
        guard confirming else { return }
        confirming = false
        refreshVisibleRows()
    }

    /// `byUser`: a key, a click or typing moved it, which Quick Look follows (`PreviewTarget`).
    func select(row: Int, byUser: Bool) {
        cancelConfirmation()
        isSelecting = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        isSelecting = false
        tableView.scrollRowToVisible(row)
        previewSelectionChanged(byUser: byUser)
        updateTile()
    }

    func setQuery(_ query: String) {
        searchField.stringValue = query
        searchField.currentEditor()?.selectedRange = NSRange(location: query.utf16.count, length: 0)
    }
}
