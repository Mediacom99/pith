import AppKit
import Carbon.HIToolbox
import LauncherCore
import Quartz

/// One line in the list.
enum Row: Equatable {
    case item(Item)
    /// A ⌘K action for the item the actions list is for.
    case action(Action)
    /// Something wrong in config.toml; ⏎ opens the file.
    case problem(String)
    /// An entry of the clipboard history.
    case clip(Clip)
    /// A ⌘K action for the clip the actions list is for.
    case clipAction(ClipAction)
    /// Above the clipboard's clips: recording paused, or the clipboard not readable.
    case notice(ClipboardNotice)
}

/// A list shown in place of the search, from ⌘K.
enum Sublist: Equatable {
    /// An item's actions.
    case actions(Item)
    /// The apps that can open a file, from Open With….
    case openWith(file: Item, apps: [Item])
    /// A clip's actions.
    case clipActions(Clip)
}

/// The search field, the tile under it and the list under that: the empty state before you type, search results while
/// you do, and an item's ⌘K actions. The tile shows what ⏎ acts on and the keys for it (decision 29).
///
/// Each keystroke searches the apps synchronously (a few hundred entries, microseconds) and the files on the file
/// engine's queue (tens of thousands, spread over the cores, well under a millisecond), then shows both merged in one
/// update. The main thread never waits for the files: a newer keystroke makes an older search's results moot.
/// Everything is laid out with fixed frames, pinned to the top: the panel is only the search bar while there's nothing
/// to list, then grows downward.
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
    var openLinks: [String: URL] = [:] {
        didSet { if openLinks != oldValue { linkApps = [:] } }
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
            stage.openCaps = keys[.open].first?.caps ?? []
            refreshVisibleRows()
            updateStage()
        }
    }
    /// What the selected row ends in, kept so drawing a row doesn't build it.
    private var openSymbol = "↩"
    /// Clipboard History's alias (decision 42), and with a space after it the prefix that opens the clipboard. Empty
    /// for neither (`[launcher] clipboard_alias`).
    var clipboardAlias = "c" {
        didSet { if clipboardAlias != oldValue { index.setAliases([clipboardAlias], for: .clipboard) } }
    }
    /// Whether a copied file is still there, and its size, read on a worker. Snapshots fix them.
    var fileFacts: @Sendable (String) -> (exists: Bool, bytes: Int?) = { path in
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return (false, nil) }
        return (true, (attributes[.size] as? NSNumber)?.intValue)
    }
    /// Quits or force-quits a running app. Tests swap it out, so they never quit a real one.
    var quitApp: (NSRunningApplication, _ force: Bool) -> Void = { app, force in
        if force { app.forceTerminate() } else { app.terminate() }
    }

    private static let resultLimit = 50
    /// How many clips the clipboard lists: five show, the rest scroll.
    private static let clipLimit = 100
    private static let recentLimit = Int(Layout.visibleRows)
    /// Added to app scores when merging with files (decision 19): about one and a half well-placed characters, so
    /// "saf" gives Safari before safari-notes.md, while a clearly better or habitual file still wins.
    private static let appHeadStart: Int32 = 24

    let searchField = NSTextField()
    let tableView = NSTableView()
    let stage = StageView(
        frame: NSRect(
            x: Layout.tileMargin, y: Layout.barHeight + 1 + Layout.tileMargin,
            width: Layout.width - 2 * Layout.tileMargin,
            height: Layout.tileHeight))
    private let separator = NSBox()
    private let scrollView = OverlayScrollView()
    private let searchIcon = NSImageView()
    private let icons = IconStore()
    let clipImages = ClipImages()
    private(set) var mode = Mode.launcher
    /// Whether the panel shows more than the search bar.
    private var isExpanded = false
    /// What `fileFacts` said, by path.
    private var facts: [String: (exists: Bool, bytes: Int?)] = [:]
    private var factsLoading: Set<String> = []
    /// The app each link scheme opens in, once looked up, for "Open in Safari".
    private var linkApps: [String: (url: URL?, name: String?)] = [:]
    /// After pinning or deleting, the clip (or the place in the list) to keep selected.
    private var keepSelection: (id: Int64, position: Int)?
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
    /// The ⌘K list showing, if any.
    private(set) var sublist: Sublist?
    /// What ⎋ goes back to, innermost last: each level's sublist (nil for the search), query, rows and selection.
    private var backStack: [(sublist: Sublist?, query: String, rows: [Row], selection: Int)] = []
    /// Force Quit, Clear Clipboard History or deleting a pinned clip is waiting for its second ⏎ (decision 28). ⎋,
    /// typing or moving the selection cancels it.
    private(set) var confirming = false

    private var panel: LauncherPanel? { viewIfLoaded?.window as? LauncherPanel }

    init(history: HistoryStore, running: RunningApps, files: FileSearchEngine) {
        self.history = history
        self.running = running
        self.files = files
        super.init(nibName: nil, bundle: nil)
        icons.onChange = { [weak self] in self?.refreshVisibleRows() }
        clipImages.onChange = { [weak self] in self?.refreshVisibleRows() }
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

        for subview in [searchIcon, searchField, separator, stage, scrollView] {
            root.addSubview(subview)
        }
        separator.isHidden = true
        stage.isHidden = true
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
        if mode != self.mode {
            self.mode = mode
            applyMode()
        }
        if mode == .clipboard { onShowClipboard() }
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
        if new == .clipboard { onShowClipboard() }
        refresh()
    }

    /// The tile's height, where the list starts, the bar's symbol and its placeholder, for the mode.
    private func applyMode() {
        let clipboard = mode == .clipboard
        stage.frame.size.height = clipboard ? Layout.clipboardTileHeight : Layout.tileHeight
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
        if !rows.isEmpty || isExpanded { show([], selecting: 0) }
    }

    // MARK: The list

    /// Recomputes the rows for the current state and query, and updates the table only if they changed. With a
    /// query, the files arrive asynchronously and the update happens then. `keystroke` (the key press time and when
    /// handling it started) is for the latency log.
    private func refresh(keystroke: (event: TimeInterval, handled: TimeInterval)? = nil) {
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
        if new != rows || isExpanded != shouldExpand(new) { show(new, selecting: selection) }
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

    private var showsEmptyClipboard: Bool {
        mode == .clipboard && sublist == nil && searchField.stringValue.allSatisfy(\.isWhitespace)
            && (clipboard?.index.count ?? 0) == 0 && clipboardNotices.isEmpty
    }

    private func show(_ new: [Row], selecting selection: Int) {
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
            select(row: min(selection, rows.count - 1))
        }
        // Only the search bar while there's nothing to list.
        let expanded = shouldExpand(rows)
        if expanded != isExpanded {
            isExpanded = expanded
            separator.isHidden = !expanded
            stage.isHidden = !expanded
            panel?.setResultsVisible(expanded)
        }
        scrollView.isHidden = rows.isEmpty
        updateStage()
    }

    private func configure(_ cell: ResultCell, for row: Row) {
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
                cell.icon.image = ClipText.paths(of: clip).first.flatMap { icons.icon(forFile: URL(filePath: $0)) }
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
                cell.title = isDanger ? ClipAction.deleteConfirmation : title(of: action, for: clip)
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
    private static func folder(of url: URL) -> String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    /// New icons or running states: update the rows on screen, and the tile, without reloading.
    private func refreshVisibleRows() {
        tableView.enumerateAvailableRowViews { rowView, row in
            guard let cell = rowView.view(atColumn: 0) as? ResultCell, tableRows.indices.contains(row) else { return }
            configure(cell, for: tableRows[row])
        }
        updateStage()
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

    /// Puts a Force Quit that's waiting for its second ⏎ back to normal.
    private func cancelConfirmation() {
        guard confirming else { return }
        confirming = false
        refreshVisibleRows()
    }

    private func select(row: Int) {
        cancelConfirmation()
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        previewSelectionChanged()
        updateStage()
    }

    private func setQuery(_ query: String) {
        searchField.stringValue = query
        searchField.currentEditor()?.selectedRange = NSRange(location: query.utf16.count, length: 0)
    }

    // MARK: The tile

    /// The field's placeholder: the item a sublist is for is on the tile, so it only says what you're filtering.
    private func placeholder(for sublist: Sublist?) -> String {
        switch sublist {
        case .actions?, .clipActions?: "Filter actions"
        case .openWith?: "Filter apps"
        case nil: mode == .clipboard ? "Search clipboard" : "Search"
        }
    }

    /// Shows what ⏎ acts on: the selected row, or in ⌘K the item the list is for, with the selected action or app as
    /// the primary key.
    private func updateStage() {
        if rows.isEmpty, showsEmptyClipboard {
            stage.content = StageView.Content(
                icon: icons.symbol(Symbols.clipboard, size: .tile), name: "Nothing copied yet",
                place: "Copy text, a link, an image or a file and it shows up here", primary: "")
            return
        }
        guard rows.indices.contains(tableView.selectedRow) else { return }
        let row = rows[tableView.selectedRow]
        let back = StageView.Key(words: "Back", caps: backCaps)
        switch sublist {
        case .actions(let item)?:
            var content = stageContent(for: item)
            guard case .action(let action) = row else { return }
            if action == .forceQuit, confirming {
                content.primary = action.title(for: item)
                content.isDanger = true
                content.secondary = StageView.Key(words: "Cancel", caps: backCaps)
            } else {
                content.primary = action.title(for: item)
                content.secondary = back
            }
            stage.content = content
        case .openWith(let file, _)?:
            var content = stageContent(for: file)
            guard case .item(let app) = row else { return }
            content.primary = "Open in \(app.name)"
            content.secondary = back
            stage.content = content
        case .clipActions(let clip)?:
            var content = stageContent(for: clip)
            guard case .clipAction(let action) = row else { return }
            content.primary = title(of: action, for: clip)
            content.secondary = back
            if action == .delete, confirming {
                content.isDanger = true
                content.secondary = StageView.Key(words: "Cancel", caps: backCaps)
            }
            stage.content = content
        case nil:
            switch row {
            case .item(let item):
                var content = stageContent(for: item)
                if confirming {
                    content.isDanger = true
                    content.secondary = StageView.Key(words: "Cancel", caps: backCaps)
                }
                stage.content = content
            case .problem(let message):
                let (title, detail) = Self.problemTile(message)
                stage.content = StageView.Content(
                    icon: icons.symbol(Symbols.problem, tint: .warning, size: .tile), name: title, place: detail,
                    kind: (ConfigStore.file.path as NSString).abbreviatingWithTildeInPath, primary: "Open Config")
            case .clip(let clip):
                stage.content = stageContent(for: clip)
            case .notice(let notice):
                stage.content = Self.noticeTile(
                    notice,
                    icon: notice == .paused
                        ? icons.symbol(Symbols.paused, size: .tile)
                        : icons.symbol(Symbols.problem, tint: .warning, size: .tile))
            case .action, .clipAction:
                break
            }
        }
    }

    /// "Actions ⌘K" on the tile, as `actions` is configured; none when it's off.
    private var actionsKey: StageView.Key? {
        keys[.actions].first.map { StageView.Key(words: "Actions", caps: $0.caps) }
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
    private func stageContent(for item: Item) -> StageView.Content {
        let actions = actionsKey
        let opened = history.history.lastOpened(item.id).map { Self.opened($0, now: now()) }
        func kind(_ parts: String?...) -> String { parts.compactMap { $0 }.joined(separator: " · ") }
        switch item.kind {
        case .app(let url):
            let isRunning = running.isRunning(item.id)
            return StageView.Content(
                icon: icons.icon(for: url, size: .tile), name: item.name, place: Self.folder(of: url),
                kind: kind("Application", isRunning ? "running" : opened), primary: "Open", secondary: actions)
        case .file(let url), .folder(let url):
            return StageView.Content(
                icon: icons.icon(forFile: url, size: .tile), name: item.name, place: Self.folder(of: url),
                kind: kind(icons.typeName(forFile: url), opened), primary: Action.open.title(for: item),
                secondary: actions)
        case .command(.clipboard):
            return StageView.Content(
                icon: icons.symbol(Symbols.command(.clipboard), size: .tile), name: item.name, place: "Pith command",
                kind: clipboardHotkey.map { "Also \($0), from any app" } ?? "", primary: "Open")
        case .command(.installUpdate):
            return StageView.Content(
                icon: icons.symbol(Symbols.command(.installUpdate), size: .tile), name: item.name,
                place: "Pith \(readyUpdate ?? "") is ready", kind: "Pith restarts into it", primary: "Restart")
        case .command(.checkForUpdates):
            return StageView.Content(
                icon: icons.symbol(Symbols.command(.checkForUpdates), size: .tile), name: item.name,
                place: "Pith command", kind: version.map { "Pith \($0)" } ?? "", primary: "Check")
        case .command(.clearClipboard):
            return StageView.Content(
                icon: icons.symbol(Symbols.command(.clearClipboard), size: .tile), name: item.name,
                place: "Pith command", kind: "Pinned items stay", primary: "Clear")
        case .command(let command):
            return StageView.Content(
                icon: icons.symbol(Symbols.command(command), size: .tile), name: item.name, place: "Pith command",
                kind: command == .quit ? version.map { "Pith \($0)" } ?? "" : "", primary: "Run")
        }
    }

    private static let timeFormat: DateFormatter = {
        let format = DateFormatter()
        format.timeStyle = .short
        format.dateStyle = .none
        return format
    }()

    /// Day and month names in English, like the rest of the copy.
    private static func englishFormat(_ template: String) -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en")
        format.setLocalizedDateFormatFromTemplate(template)
        return format
    }
    private static let weekdayFormat = englishFormat("EEEE")
    private static let dayFormat = englishFormat("MMMd")

    /// "opened today at 14:05", "opened yesterday", "opened Tuesday" within the week, else "opened Nov 3".
    static func opened(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "opened today at \(timeFormat.string(from: date))" }
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? .max
        if days == 1 { return "opened yesterday" }
        if (2..<7).contains(days) { return "opened \(weekdayFormat.string(from: date))" }
        return "opened \(dayFormat.string(from: date))"
    }

    // MARK: Quick Look

    /// The selected file or folder, which Quick Look previews (FEATURES.md §4.2), or the clipboard's image or first
    /// file.
    var previewURL: URL? {
        let row = tableView.selectedRow
        guard sublist == nil, rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case .item(let item):
            switch item.kind {
            case .file(let url), .folder(let url): return url
            case .app, .command: return nil
            }
        case .clip(let clip):
            switch clip.kind {
            case .image: return clipboard?.store.imageFile(of: clip.id)
            case .files: return ClipText.paths(of: clip).first.map { URL(filePath: $0) }
            case .text, .richText, .link: return nil
            }
        case .action, .problem, .notice, .clipAction:
            return nil
        }
    }

    private var quickLook: QLPreviewPanel? {
        QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
    }

    var isPreviewing: Bool { quickLook?.isVisible == true }

    /// Shows or hides the preview of the selected file (⌘Y, or Space with an empty field: decision 20). The keyboard
    /// stays with the launcher, so ↑/↓ move through the results and the preview follows.
    func togglePreview() {
        if isPreviewing {
            closePreview()
            return
        }
        guard previewURL != nil, let preview = QLPreviewPanel.shared(), let window = view.window else { return }
        preview.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        preview.updateController()
        preview.orderFront(nil)
        preview.reloadData()
    }

    func closePreview() {
        quickLook?.orderOut(nil)
    }

    private func previewSelectionChanged() {
        guard isPreviewing else { return }
        if previewURL == nil { closePreview() } else { quickLook?.reloadData() }
    }

    // Quick Look's controller hooks, declared nonisolated on NSObject; AppKit calls them on the main thread.

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    // MARK: ⌘K

    /// The open actions list, in full, unfiltered: each action's place in it is its shortcut.
    private var allActions: [Row] {
        switch sublist {
        case .actions(let item)?:
            Action.available(for: item, running: running.isRunning(item.id)).map(Row.action)
        case .clipActions(let clip)?:
            ClipAction.available(for: clip, canPaste: canPaste).map(Row.clipAction)
        case .openWith?, nil:
            []
        }
    }

    /// An action row's shortcut, as the row shows it: "⌘Q" for the first action, "⌘W" for the second… Fixed per
    /// action, so filtering doesn't change it (decision 43).
    private func shortcut(for row: Row) -> String? {
        guard let position = allActions.firstIndex(of: row), position < keys.runActions.count else { return nil }
        return keys.runActions[position]?.symbols
    }

    /// The nth of `run_actions` in an actions list: runs the nth action as ⏎ would on its row, the filter cleared if
    /// it hid it. A second press confirms Force Quit or a pinned clip's Delete, as a second ⏎ does. False when there's
    /// no such action here.
    func runAction(at position: Int) -> Bool {
        let actions = allActions
        guard position < actions.count else { return false }
        let action = actions[position]
        if !rows.contains(action) {
            setQuery("")
            refresh()
        }
        guard let row = rows.firstIndex(of: action) else { return false }
        // Selecting another row cancels a confirmation; the same row keeps it, for the second press.
        if tableView.selectedRow != row { select(row: row) }
        activate(row: row)
        return true
    }

    /// Lists the selected item's actions, or goes back to the search.
    func toggleActions() {
        if sublist != nil {
            while sublist != nil { goBack() }
            return
        }
        let selection = tableView.selectedRow
        guard rows.indices.contains(selection) else { return }
        if case .clip(let clip) = rows[selection] {
            enter(.clipActions(clip))
            return
        }
        guard case .item(let item) = rows[selection], !Action.available(for: item, running: false).isEmpty else {
            return
        }
        enter(.actions(item))
    }

    /// Shows `sublist` in place of what's showing; ⎋ comes back to it as it is.
    private func enter(_ new: Sublist) {
        backStack.append((sublist, searchField.stringValue, rows, tableView.selectedRow))
        sublist = new
        searchField.placeholderString = placeholder(for: new)
        setQuery("")
        refresh()
    }

    /// Back one level, as it was: same query, rows and selection, without searching again.
    private func goBack() {
        guard let previous = backStack.popLast() else { return }
        sublist = previous.sublist
        searchGeneration += 1  // a search still in flight would overwrite the restored rows
        searchField.placeholderString = placeholder(for: previous.sublist)
        setQuery(previous.query)
        show(previous.rows, selecting: previous.selection)
    }

    // MARK: Opening

    @objc private func activateClickedRow() {
        activate(row: tableView.clickedRow)
    }

    private func activate(row: Int) {
        guard rows.indices.contains(row) else { return }
        switch (rows[row], sublist) {
        case (.item(let app), .openWith(let file, _)?):
            history.record(file.id)
            panel?.dismiss()
            if let url = file.url, let appURL = app.url { open(url, with: appURL) }
        case (.item(let item), _):
            if case .command(.clearClipboard) = item.kind, !confirming {
                confirming = true
                refreshVisibleRows()
                return
            }
            open(item)
        case (.action(let action), .actions(let item)?):
            if action == .forceQuit, !confirming {
                confirming = true
                refreshVisibleRows()
                return
            }
            perform(action, on: item)
        case (.action, _):
            break
        case (.problem, _):
            panel?.dismiss()
            runCommand(.openConfig)
        case (.clip(let clip), _):
            perform(canPaste ? .paste : .copy, on: clip)
        case (.clipAction(let action), .clipActions(let clip)?):
            perform(action, on: clip)
        case (.clipAction, _):
            break
        case (.notice(let notice), _):
            if notice != .paused { panel?.dismiss() }
            resolveNotice(notice)
        }
    }

    private func open(_ item: Item) {
        history.record(item.id)
        // Clipboard History opens in place: the panel stays, as the clipboard.
        if case .command(.clipboard) = item.kind {
            switchMode(to: .clipboard)
            return
        }
        panel?.dismiss()
        switch item.kind {
        case .app(let url): openApp(at: url)
        case .file(let url): openFile(at: url)
        case .folder(let url): open(url, with: nil)
        case .command(let command): runCommand(command)
        }
    }

    /// Opens a file in the app `[open_with]` sets for its type, else its default app.
    private func openFile(at url: URL) {
        let openWith = openWithApps
        Task {
            let app = await runInBackground(qos: .userInitiated) { AppResolver.app(forFile: url, openWith: openWith) }
            open(url, with: app)
        }
    }

    /// Opens `url` in `app`, or in its default app.
    private func open(_ url: URL, with app: URL?) {
        Task {
            do {
                if let app {
                    _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: .init())
                } else {
                    _ = try await NSWorkspace.shared.open(url, configuration: .init())
                }
            } catch {
                let name = url.lastPathComponent
                let title = app.map { "Couldn't open \(name) in \($0.deletingPathExtension().lastPathComponent)" }
                failed(title ?? "Couldn't open \(name)", url, error)
            }
        }
    }

    /// An action that failed after the panel closed: logged, and reported (decision 32).
    private func failed(_ title: String, _ item: URL?, _ error: any Error) {
        failed(title, item, reason: error.localizedDescription)
    }

    fileprivate func failed(_ title: String, _ item: URL?, reason: String) {
        Log.app.error("\(title, privacy: .public) (\(item?.path ?? "", privacy: .public)): \(reason, privacy: .public)")
        reportFailure(title, item, reason)
    }

    private func perform(_ action: Action, on item: Item) {
        guard let url = item.url else { return }
        if action == .openWith {
            let apps = knownApps
            Task {
                let choices = await runInBackground(qos: .userInitiated) { AppResolver.apps(toOpen: url, among: apps) }
                enter(.openWith(file: item, apps: choices))
            }
            return
        }
        panel?.dismiss()
        switch action {
        case .open:
            open(item)
        case .reveal:
            Task {
                await runInBackground(qos: .userInitiated) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        case .copyPath:
            Task {
                await runInBackground(qos: .userInitiated) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            }
        case .copyItem:
            // The file itself, to paste in Finder, Mail, Slack…
            Task {
                await runInBackground(qos: .userInitiated) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([url as NSURL])
                }
            }
        case .openInTerminal:
            open(url, with: terminalApp)
        case .zip:
            notifier?.zip(url)
        case .trash:
            Task {
                let failure = await runInBackground(qos: .userInitiated) { () -> (any Error)? in
                    do {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        return nil
                    } catch {
                        return error
                    }
                }
                if let failure {
                    failed("Couldn't move \(url.lastPathComponent) to the Trash", url, failure)
                } else {
                    history.forget(paths: [url.path])
                }
            }
        case .quit:
            if let app = running.application(item.id) { quitApp(app, false) }
        case .forceQuit:
            if let app = running.application(item.id) { quitApp(app, true) }
        case .openWith:
            break
        }
    }

    /// The indexed apps, for resolving app names and naming the Open With… choices.
    var knownApps: [AppResolver.App] {
        index.items.compactMap { item in
            guard item.isApp, let url = item.url else { return nil }
            return AppResolver.App(names: [item.name, url.deletingPathExtension().lastPathComponent], url: url)
        }
    }

    /// Launches the app, or brings it to the front if it's running.
    private func openApp(at url: URL) {
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            } catch {
                failed("Couldn't open \(url.deletingPathExtension().lastPathComponent)", url, error)
            }
        }
    }
}

// MARK: The clipboard

extension LauncherViewController {
    /// The notices, then the clips matching `query` (newest first, pinned first once you type: decision 33), with
    /// the newest clip selected.
    fileprivate func clipRows(matching query: String) -> (rows: [Row], selection: Int) {
        guard let clipboard else { return ([], 0) }
        let notices = query.allSatisfy(\.isWhitespace) ? clipboardNotices.map(Row.notice) : []
        let index = clipboard.index
        let clips = index.search(query, limit: Self.clipLimit).map { Row.clip(index.clips[$0]) }
        return (notices + clips, clips.isEmpty ? 0 : notices.count)
    }

    /// A new copy, or clips pinned or dropped: ready the newest images, and show the change if the clipboard is up.
    func clipboardChanged() {
        guard let clipboard else { return }
        clipImages.preload(clipboard.index, store: clipboard.store)
        if mode == .clipboard, sublist == nil { refresh() }
    }

    /// The app a text or link was copied from, or the kind's symbol when there's no such app; nil while it's looked up,
    /// so a row doesn't show the symbol, then the app.
    fileprivate func sourceIcon(of clip: Clip, size: IconSize) -> CGImage? {
        if let source = clip.source, !icons.isMissing(bundleID: source) {
            return icons.icon(forBundleID: source, size: size)
        }
        return icons.symbol(clip.kind == .link ? Symbols.link : Symbols.text, size: size)
    }

    /// Source apps still being looked up, for snapshots to wait on.
    var isResolvingApps: Bool { icons.isResolvingApps }

    /// The tile for a clip (docs/BRIEF-CLIPBOARD.md §5): a text as it will paste, an image in its box, a link or files
    /// as an item. ⏎ pastes it, or copies it without Accessibility access.
    fileprivate func stageContent(for clip: Clip) -> StageView.Content {
        let source = clip.source.flatMap { icons.appName(forBundleID: $0) }
        let now = now()
        let primary = canPaste ? "Paste" : "Copy"
        let actions = actionsKey
        switch clip.kind {
        case .text, .richText:
            let preview = ClipText.preview(of: clip)
            let size = clip.textBytes >= ClipText.longText ? ClipText.bytes(clip.textBytes) : ""
            return StageView.Content(
                name: "",
                kind: ClipText.about(
                    [ClipText.kindName(clip.kind), ClipText.detail(of: clip), size], copied: clip.copied, from: source,
                    now: now),
                primary: primary, secondary: actions,
                preview: .text(preview, isBlank: preview.allSatisfy(\.isWhitespace)))
        case .link:
            return StageView.Content(
                icon: sourceIcon(of: clip, size: .tile), name: ClipText.host(of: clip), place: clip.text,
                kind: ClipText.about(["Link"], copied: clip.copied, from: source, now: now), primary: primary,
                secondary: actions, placeLines: 3)
        case .image:
            let image = clipboard.flatMap { clipImages.preview(clip, store: $0.store) }
            let when = ClipText.copied(clip.copied, now: now) + (source.map { " from \($0)" } ?? "")
            return StageView.Content(
                name: "Image",
                place: "\(ClipText.detail(of: clip)) · PNG · \(ClipText.bytes(clip.size))",
                kind: when.prefix(1).uppercased() + when.dropFirst(), primary: primary, secondary: actions,
                preview: .image(image, size: ClipText.previewSize(of: clip)))
        case .files:
            let paths = ClipText.paths(of: clip)
            let known = paths.compactMap(fileFact)
            let gone = paths.count == 1 && known.first?.exists == false
            let bytes = known.count == paths.count ? known.compactMap(\.bytes).reduce(0, +) : nil
            let first = paths.first.map { URL(filePath: $0) }
            let kind =
                paths.count > 1 ? "\(paths.count) files" : first.flatMap { icons.typeName(forFile: $0) } ?? ""
            return StageView.Content(
                icon: first.flatMap { icons.icon(forFile: $0, size: .tile) }, name: ClipText.title(of: clip).text,
                place: gone ? "No longer in \(ClipText.folders(of: clip))" : ClipText.folders(of: clip),
                kind: ClipText.about(
                    [kind, bytes.map(ClipText.bytes) ?? ""], copied: clip.copied, from: source, now: now),
                primary: primary, secondary: actions)
        }
    }

    /// Whether a copied file is still there and its size, once read on a worker; the tile updates when it is.
    private func fileFact(_ path: String) -> (exists: Bool, bytes: Int?)? {
        if let fact = facts[path] { return fact }
        if factsLoading.insert(path).inserted {
            let read = fileFacts
            Task {
                let fact = await runInBackground(qos: .userInitiated) { read(path) }
                factsLoading.remove(path)
                facts[path] = fact
                updateStage()
            }
        }
        return nil
    }

    /// What Clear Clipboard History's row says while it waits for its second ⏎.
    static let clearConfirmation = "Press ⏎ again to clear the clipboard history"

    static func noticeTitle(_ notice: ClipboardNotice) -> String {
        switch notice {
        case .paused: "Recording is paused"
        case .cannotRead: "Pith can't read the clipboard"
        case .needsAccessibility: "Paste needs Accessibility access"
        }
    }

    fileprivate static func noticeTile(_ notice: ClipboardNotice, icon: CGImage?) -> StageView.Content {
        switch notice {
        case .paused:
            StageView.Content(
                icon: icon, name: noticeTitle(notice), place: "Copies aren't saved until you resume", primary: "Resume")
        case .cannotRead:
            StageView.Content(
                icon: icon, name: noticeTitle(notice), place: "macOS is set to deny it, so copies aren't saved",
                kind: "System Settings, Privacy & Security", primary: "Open Settings")
        case .needsAccessibility:
            StageView.Content(
                icon: icon, name: noticeTitle(notice), place: "Until it's allowed, ⏎ copies instead of pasting",
                kind: "System Settings, Privacy & Security, Accessibility", primary: "Open Settings")
        }
    }

    /// A clip's ⌘K action's name: "Paste", "Open in Safari"…
    fileprivate func title(of action: ClipAction, for clip: Clip) -> String {
        action.title(canPaste: canPaste, linkApp: action == .openLink ? linkApp(for: clip)?.name : nil)
    }

    /// Runs a clip action (docs/BRIEF-CLIPBOARD.md §6). Pinning and deleting keep the panel open and go back to the
    /// list; everything else closes it first, so a paste lands in the app you were in.
    fileprivate func perform(_ action: ClipAction, on clip: Clip) {
        switch action {
        case .pin, .unpin:
            keepSelection = (clip.id, backStack.last?.selection ?? tableView.selectedRow)
            if sublist != nil { goBack() }
            Task { await clipboard?.setPinned(action == .pin, for: clip.id) }
            return
        case .delete:
            if clip.pinned, !confirming {
                confirming = true
                refreshVisibleRows()
                return
            }
            keepSelection = (-1, backStack.last?.selection ?? tableView.selectedRow)
            if sublist != nil { goBack() }
            Task { await clipboard?.delete(clip.id) }
            return
        default:
            break
        }
        panel?.dismiss()
        switch action {
        case .paste: deliverClip(clip, .paste)
        case .copy:
            deliverClip(clip, .copy)
            // The first ⏎ without access asks for it.
            if !canPaste { askForAccessibility() }
        case .pastePlainText: deliverClip(clip, canPaste ? .pastePlainText : .copyPlainText)
        case .openLink:
            if let url = URL(string: clip.text) { open(url, with: linkApp(for: clip)?.url) }
        case .reveal: reveal(clip)
        case .save: save(clip)
        case .pin, .unpin, .delete: break
        }
    }

    /// Puts the clip back on the clipboard, then presses ⌘V for a paste. Plain text is the clip itself, so it's marked
    /// for the history to skip, and the clip moves to the top as a copy would.
    fileprivate func deliver(_ clip: Clip, _ delivery: ClipDelivery) {
        guard let clipboard else { return }
        let store = clipboard.store
        Task {
            do throws(ClipboardStore.Failure) {
                if delivery.isPlainText {
                    let text = try await store.text(of: clip.id)
                    let plain = [
                        [Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]
                    ]
                    await runInBackground(qos: .userInitiated) {
                        Paster.write(plain, source: clip.source, transient: true)
                        if delivery.presses { Paster.pressCommandV() }
                    }
                    await clipboard.moveToTop(clip.id)
                } else {
                    let items = try await store.items(of: clip.id)
                    await runInBackground(qos: .userInitiated) {
                        Paster.write(items, source: clip.source, transient: false)
                        if delivery.presses { Paster.pressCommandV() }
                    }
                }
            } catch {
                failed(
                    delivery.presses ? "Couldn't paste the clip" : "Couldn't copy the clip", nil,
                    reason: error.description)
            }
        }
    }

    /// The app a link opens in: `[open_links]`'s for its scheme, else the default, looked up on a worker the first
    /// time; nil until then.
    private func linkApp(for clip: Clip) -> (url: URL?, name: String?)? {
        guard let url = URL(string: clip.text), let scheme = url.scheme?.lowercased() else { return nil }
        if let known = linkApps[scheme] { return known }
        linkApps[scheme] = (nil, nil)
        let configured = openLinks[scheme]
        Task {
            let app = await runInBackground(qos: .userInitiated) { () -> (url: URL?, name: String?) in
                guard let app = configured ?? NSWorkspace.shared.urlForApplication(toOpen: url) else {
                    return (nil, nil)
                }
                let name = FileManager.default.displayName(atPath: app.path)
                return (app, name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
            }
            linkApps[scheme] = app
            refreshVisibleRows()
        }
        return nil
    }

    /// Shows the clip's files in Finder, or says they're gone.
    private func reveal(_ clip: Clip) {
        let urls = ClipText.paths(of: clip).map { URL(filePath: $0) }
        let read = fileFacts
        Task {
            let present = await runInBackground(qos: .userInitiated) { () -> [URL] in
                let present = urls.filter { read($0.path).exists }
                if !present.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(present) }
                return present
            }
            if present.isEmpty, let first = urls.first {
                failed(
                    "Couldn't reveal \(first.lastPathComponent)", nil,
                    reason: "It was moved or deleted since it was copied")
            }
        }
    }

    /// Saves a text or an image to `saveFolder` with a dated name, then says where (decision 39).
    private func save(_ clip: Clip) {
        guard let store = clipboard?.store else { return }
        let folder = saveFolder
        let date = now()
        Task {
            do throws(ClipboardStore.Failure) {
                let data: Data
                let ext: String
                if clip.kind == .image {
                    let file = store.imageFile(of: clip.id)
                    guard let image = await runInBackground(qos: .userInitiated, { try? Data(contentsOf: file) }) else {
                        throw ClipboardStore.Failure(description: "the image is no longer in the history")
                    }
                    (data, ext) = (image, "png")
                } else {
                    (data, ext) = (Data(try await store.text(of: clip.id).utf8), "txt")
                }
                let saved = await runInBackground(qos: .userInitiated) { () -> Result<URL, ClipboardStore.Failure> in
                    let file = ClipFiles.destination(in: folder, at: date, extension: ext)
                    do {
                        try data.write(to: file, options: .withoutOverwriting)
                        return .success(file)
                    } catch {
                        return .failure(ClipboardStore.Failure(description: error.localizedDescription))
                    }
                }
                reportSaved(try saved.get())
            } catch {
                failed("Couldn't save the clip", nil, reason: error.description)
            }
        }
    }
}

extension LauncherViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        // `c ` in the launcher's field opens the clipboard (FEATURES.md §4), or the alias configured.
        if mode == .launcher, sublist == nil, !clipboardAlias.isEmpty,
            searchField.stringValue.lowercased() == clipboardAlias + " "
        {
            switchMode(to: .clipboard)
            return
        }
        let handled = ProcessInfo.processInfo.systemUptime
        refresh(keystroke: NSApp.currentEvent.map { ($0.timestamp, handled) })
    }

    /// The panel's keys are looked up before the field editor sees them (`handleKey`). A ⏎ or ⎋ that isn't one of
    /// them does nothing here, rather than end the field's editing; other keys edit the field as usual.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:))
    }
}

// MARK: Keys

extension LauncherViewController {
    /// A key press, as `Shortcut.matches` compares it.
    struct KeyPress {
        var keyCode: UInt32
        var modifiers: UInt32
        var character: String?

        init(_ event: NSEvent) {
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            keyCode = UInt32(event.keyCode)
            modifiers =
                (flags.contains(.command) ? UInt32(cmdKey) : 0) | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
                | (flags.contains(.option) ? UInt32(optionKey) : 0)
                | (flags.contains(.control) ? UInt32(controlKey) : 0)
            // What the key types with ⌘ alone, so ⇧ and ⌥ don't change the letter, and a layout that turns QWERTY
            // under ⌘ still finds ⌘K.
            character =
                (event.characters(byApplyingModifiers: flags.intersection(.command))
                ?? event.charactersIgnoringModifiers)?.lowercased()
        }
    }

    /// The order keys are looked up in: `back` and `open` first, as they get their default back when a setting
    /// leaves them with none, even if another setting has it (decision 55).
    private static let lookupOrder: [PanelKey] = [.back, .open, .up, .down, .actions, .preview, .toLauncher]

    /// What a key press does in the panel (decision 55). True when it's taken: it did something, or it's one of the
    /// panel's keys that doesn't type. A key that types (a letter, Space, ⌫) acts only while the field is empty, and
    /// otherwise goes on to the field. In an actions list, `run_actions` comes first.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let press = KeyPress(event)
        let isEmpty = searchField.stringValue.isEmpty
        func usable(_ shortcut: Shortcut?) -> Shortcut? {
            guard let shortcut,
                shortcut.matches(keyCode: press.keyCode, modifiers: press.modifiers, character: press.character),
                isEmpty || !shortcut.typesText
            else { return nil }
            return shortcut
        }
        if sublist != nil {
            for (position, shortcut) in keys.runActions.enumerated() where usable(shortcut) != nil {
                if runAction(at: position) { return true }
            }
        }
        for key in Self.lookupOrder {
            guard let shortcut = keys[key].lazy.compactMap(usable).first else { continue }
            return perform(key) || !shortcut.typesText
        }
        return false
    }

    /// Does what `key` does here; false when it doesn't apply now (nothing to preview, not in the clipboard).
    private func perform(_ key: PanelKey) -> Bool {
        switch key {
        case .up: moveSelection(by: -1)
        case .down: moveSelection(by: 1)
        case .open: activate(row: tableView.selectedRow)
        case .actions: toggleActions()
        case .back:
            if isPreviewing {
                closePreview()
            } else if confirming {
                cancelConfirmation()
            } else if sublist != nil {
                goBack()
            } else {
                panel?.dismiss()
            }
        case .preview:
            guard isPreviewing || previewURL != nil else { return false }
            togglePreview()
        case .toLauncher:
            // From the clipboard's empty field back to the launcher.
            guard mode == .clipboard, sublist == nil, searchField.stringValue.isEmpty else { return false }
            switchMode(to: .launcher)
        case .runActions:
            return false
        }
        return true
    }

    /// Whether `event` is one of `key`'s shortcuts: Quick Look's window, when it has the keyboard, moves through the
    /// results with them.
    func isKey(_ key: PanelKey, _ event: NSEvent) -> Bool {
        let press = KeyPress(event)
        return keys[key].contains {
            $0.matches(keyCode: press.keyCode, modifiers: press.modifiers, character: press.character)
        }
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

    /// A click on another row also cancels a Force Quit waiting for its second ⏎.
    func tableViewSelectionDidChange(_ notification: Notification) {
        cancelConfirmation()
    }
}

/// Overlay scrollers whatever System Settings says: an always-visible scroller would take 15 pt off the rows, so a
/// list that scrolls would be narrower than one that doesn't.
final class OverlayScrollView: NSScrollView {
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }
}

extension LauncherViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewURL.map { $0 as NSURL }
    }

    /// Keys pressed while the preview has the focus (after a click on it): `up` and `down` keep moving through the
    /// results.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown else { return false }
        if isKey(.down, event) {
            moveSelection(by: 1)
        } else if isKey(.up, event) {
            moveSelection(by: -1)
        } else {
            return false
        }
        return true
    }
}
