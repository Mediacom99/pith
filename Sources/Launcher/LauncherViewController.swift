import AppKit
import LauncherCore

/// The search field and the result list.
///
/// Searching runs synchronously on the main thread: the app index holds a few hundred entries and a search takes
/// microseconds (`make bench`).
final class LauncherViewController: NSViewController {
    var index = AppIndex.empty {
        didSet { search() }
    }

    private static let resultLimit = 50

    private let searchField = NSTextField()
    private let separator = NSBox()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let icons = IconCache()
    /// Indices into `index.apps`, best match first.
    private var results: [Int] = []

    private var panel: LauncherPanel? { viewIfLoaded?.window as? LauncherPanel }

    override func loadView() {
        let size = NSRect(x: 0, y: 0, width: Layout.width, height: Layout.barHeight)

        let searchIcon = NSImageView(
            image: NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil) ?? NSImage()
        )
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

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: Layout.resultsInset, left: 0, bottom: Layout.resultsInset, right: 0)

        let content = NSView(frame: size)
        content.autoresizingMask = [.width, .height]
        for subview in [searchIcon, searchField, separator, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        // Gives way when the panel shrinks to the search bar.
        let resultsBottom = scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        resultsBottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            searchIcon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            searchIcon.centerYAnchor.constraint(equalTo: content.topAnchor, constant: Layout.barHeight / 2),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            searchField.centerYAnchor.constraint(equalTo: searchIcon.centerYAnchor),
            separator.topAnchor.constraint(equalTo: content.topAnchor, constant: Layout.barHeight),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0),
            resultsBottom,
        ])

        let glass = NSGlassEffectView(frame: size)
        glass.cornerRadius = Layout.cornerRadius
        glass.contentView = content
        view = glass
        showResults(false)
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    func reset() {
        searchField.stringValue = ""
        search()
    }

    private func search() {
        results = index.search(searchField.stringValue, limit: Self.resultLimit)
        tableView.reloadData()
        if !results.isEmpty { select(row: 0) }
        showResults(!results.isEmpty)
    }

    private func showResults(_ visible: Bool) {
        separator.isHidden = !visible
        scrollView.isHidden = !visible
        panel?.setResultsVisible(visible)
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
        search()
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
        cell.imageView?.image = icons.icon(for: app.url)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        tableView.makeView(withIdentifier: ResultRowView.identifier, owner: nil) as? ResultRowView ?? ResultRowView()
    }
}
