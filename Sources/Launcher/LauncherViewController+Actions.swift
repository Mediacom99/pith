import AppKit
import LauncherCore

// MARK: ⌘K

extension LauncherViewController {
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
    func shortcut(for row: Row) -> String? {
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
        if tableView.selectedRow != row { select(row: row, byUser: true) }
        activate(row: row, byShortcut: true)
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
    func goBack() {
        guard let previous = backStack.popLast() else { return }
        sublist = previous.sublist
        searchGeneration += 1  // a search still in flight would overwrite the restored rows
        searchField.placeholderString = placeholder(for: previous.sublist)
        setQuery(previous.query)
        show(previous.rows, selecting: previous.selection, byUser: true)
        // Back at the clipboard after copies or deletions landed behind the actions: the list as it is now.
        if clipsChangedBehind, sublist == nil {
            clipsChangedBehind = false
            clipboardChanged()
        }
    }
}

// MARK: Opening

extension LauncherViewController {
    @objc func activateClickedRow() {
        activate(row: tableView.clickedRow)
    }

    /// Does what ⏎ does on `row`: opens it, runs it, or asks for a second ⏎ first (decision 28).
    /// `byShortcut`: a `run_actions` key ran it, rather than ⏎ or a double click.
    func activate(row: Int, byShortcut: Bool = false) {
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
            // ⏎ meant to paste: without access it copies, and the first time asks for it. Copy to Clipboard doesn't.
            if !canPaste { askForAccessibility() }
        case (.clipAction(let action), .clipActions(let clip)?):
            perform(action, on: clip, byShortcut: byShortcut)
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
        case .settingsPage: if let url = item.settingsURL { open(url, with: nil) }
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
    func open(_ url: URL, with app: URL?) {
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

    func failed(_ title: String, _ item: URL?, reason: String) {
        Log.app.error("\(title, privacy: .public) (\(item?.path ?? "", privacy: .public)): \(reason, privacy: .public)")
        reportFailure(title, item, reason)
    }

    /// Runs an item's ⌘K action. Open With… lists the apps in place; everything else closes the panel first.
    private func perform(_ action: Action, on item: Item) {
        guard let url = item.url else { return }
        if action == .openWith { return listApps(toOpen: item, at: url) }
        panel?.dismiss()
        switch action {
        case .open:
            open(item)
        case .reveal:
            Task {
                await runInBackground(qos: .userInitiated) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        case .copyPath:
            putOnClipboard { $0.setString(url.path, forType: .string) }
        case .copyItem:
            // The file itself, to paste in Finder, Mail, Slack…
            putOnClipboard { $0.writeObjects([url as NSURL]) }
        case .openInTerminal:
            open(url, with: terminalApp)
        case .zip:
            notifier?.zip(url)
        case .trash:
            moveToTrash(url)
        case .quit:
            if let app = running.application(item.id) { quitApp(app, false) }
        case .forceQuit:
            if let app = running.application(item.id) { quitApp(app, true) }
        case .openWith:
            break
        }
    }

    /// Open With…: the apps that can open the file, looked up on a worker, listed in place of the actions.
    private func listApps(toOpen item: Item, at url: URL) {
        let apps = knownApps
        let from = (sublist, backStack.count)
        Task {
            let choices = await runInBackground(qos: .userInitiated) { AppResolver.apps(toOpen: url, among: apps) }
            // Only if the panel is still where Open With… was chosen: not closed, left or already in it.
            guard sublist == from.0, backStack.count == from.1 else { return }
            // Apps outside the indexed folders (Archive Utility, one in Downloads) have no icon yet.
            icons.add(apps: choices.compactMap(\.url))
            enter(.openWith(file: item, apps: choices))
        }
    }

    /// Replaces the clipboard's contents with what `write` puts there, on a worker: the pasteboard is IPC.
    private func putOnClipboard(_ write: @escaping @Sendable (NSPasteboard) -> Void) {
        Task {
            await runInBackground(qos: .userInitiated) {
                NSPasteboard.general.clearContents()
                write(NSPasteboard.general)
            }
        }
    }

    /// Moves the file or folder to the Trash on a worker, and forgets it in the history.
    private func moveToTrash(_ url: URL) {
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
