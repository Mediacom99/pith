import AppKit
import Carbon.HIToolbox
import LauncherCore
import TestSupport
import Testing

@testable import Launcher

/// A real panel, laid out and drawn but never ordered onto the screen. Its history lives in a temporary file and
/// starts with `opened`, oldest first.
func makePanel(
    items: [Item], opened: [String] = [], emptyState: Config.EmptyState = .none, problems: [String] = [],
    files: FileSearchEngine = FileSearchEngine()
) -> LauncherPanel {
    _ = NSApplication.shared
    // One shared scratch file: tests read the history from memory, so its contents don't matter, and nothing piles up.
    let history = HistoryStore(
        file: FileManager.default.temporaryDirectory.appending(path: "PithTests-history.json"))
    for id in opened { history.record(id) }
    let launcher = LauncherViewController(history: history, running: RunningApps(), files: files)
    launcher.emptyState = emptyState
    launcher.problems = problems
    let panel = LauncherPanel(launcher: launcher)
    launcher.index = SearchIndex(items: items)
    return panel
}

/// Types `text` and waits for the search, files included, to land.
func type(_ text: String, in panel: LauncherPanel) async {
    panel.launcher.searchField.stringValue = text
    panel.launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    await panel.launcher.pendingSearch?.value
    panel.layoutIfNeeded()
}

/// Presses `key` ("down", "return", "cmd+k"), as the keyboard would: through the panel's keys (decision 55). True
/// when the panel took it; false when it would go on to the search field.
@discardableResult
func press(_ key: String, in panel: LauncherPanel) -> Bool {
    let shortcut = Shortcut(key)!
    var flags: NSEvent.ModifierFlags = []
    for (carbon, flag) in [(cmdKey, NSEvent.ModifierFlags.command), (shiftKey, .shift), (optionKey, .option)]
        + [(controlKey, NSEvent.ModifierFlags.control)]
    where shortcut.modifiers & UInt32(carbon) != 0 {
        flags.insert(flag)
    }
    let characters =
        switch shortcut.key {
        case "return": "\r"
        case "escape": "\u{1b}"
        case "backspace": "\u{7f}"
        case "space": " "
        case "tab": "\t"
        case "up": String(UnicodeScalar(UInt16(NSUpArrowFunctionKey))!)
        case "down": String(UnicodeScalar(UInt16(NSDownArrowFunctionKey))!)
        default: shortcut.key
        }
    let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: panel.windowNumber,
        context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
        keyCode: UInt16(shortcut.keyCode))!
    return panel.handleKey(event)
}

/// Made-up apps, so none of them is running on the machine that runs the tests.
private let apps = ["Gizmo", "Gadget Pro", "Widget", "Hollow Thing", "Sprocket"].map {
    Item(name: $0, appAt: URL(filePath: "/nonexistent/\($0).app"))
}

private func names(_ rows: [Row], for item: Item? = nil) -> [String] {
    rows.map {
        switch $0 {
        case .item(let item): item.name
        case .action(let action): item.map(action.title(for:)) ?? "\(action)"
        case .problem(let message): message
        case .clip(let clip): ClipText.title(of: clip).text
        case .notice(let notice): LauncherViewController.noticeTitle(notice)
        case .clipAction(let action): action.title(canPaste: false, linkApp: nil)
        }
    }
}

/// What the panel lists, with action titles for the item they're for.
private func names(_ panel: LauncherPanel) -> [String] {
    if case .actions(let item)? = panel.launcher.sublist { return names(panel.launcher.rows, for: item) }
    return names(panel.launcher.rows)
}

/// Polls `condition` on the main actor until it holds or a few seconds pass, for work that hops through a worker.
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(25)) }
    return condition()
}

struct LauncherPanelTests {
    @Test func opensAsJustTheSearchBarWhenTheEmptyStateIsNone() {
        let panel = makePanel(items: apps, opened: [apps[0].id])
        panel.launcher.prepareToShow()
        #expect(panel.launcher.rows.isEmpty)
        #expect(panel.frame.height == Layout.barHeight)
    }

    @Test func growsWithResultsAndShrinksKeepingTheTopEdge() async {
        let panel = makePanel(items: apps)
        let top = panel.frame.maxY

        await type("g", in: panel)
        #expect(panel.frame.height == Layout.expandedHeight)
        #expect(panel.frame.maxY == top)

        await type("gqqq", in: panel)
        #expect(panel.frame.height == Layout.barHeight)
        #expect(panel.frame.maxY == top)
    }

    /// NSTableView fades rows added to a list on screen in over ~200 ms; the list must change in one frame.
    @Test func rowsAddedToAListOnScreenShowAtOnce() async {
        let panel = makePanel(items: apps)
        func transparentRows() -> [Int] {
            var rows: [Int] = []
            panel.launcher.tableView.enumerateAvailableRowViews { view, row in
                if view.alphaValue < 1 { rows.append(row) }
            }
            return rows
        }
        await type("giz", in: panel)
        panel.displayIfNeeded()

        await type("g", in: panel)
        #expect(panel.launcher.rows.count == 4, "Gizmo, Gadget Pro, Widget, Hollow Thing")
        #expect(transparentRows().isEmpty, "a broader query")

        panel.launcher.toggleActions()
        press("escape", in: panel)
        panel.layoutIfNeeded()
        #expect(transparentRows().isEmpty, "⎋ from two actions back to four results")
    }

    @Test func rowsSpanThePanelAndNamesAreWhole() async throws {
        let panel = makePanel(items: apps)
        await type("giz", in: panel)
        let cell = try #require(
            panel.launcher.tableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? ResultCell)
        cell.layoutSubtreeIfNeeded()
        let title = try #require(cell.textField)
        #expect(title.stringValue == "Gizmo")
        #expect(cell.frame.width > Layout.width - 60, "the column spans the table")
        let needed = try #require(title.cell).cellSize.width
        #expect(title.frame.width >= needed, "the name isn't cut")
    }

    /// The tile shows what ⏎ acts on, and follows the selection; in ⌘K the item stays and the keys change.
    @Test func theTileShowsWhatReturnActsOn() async {
        let panel = makePanel(items: apps)
        let stage = panel.launcher.stage
        await type("g", in: panel)
        #expect(!stage.isHidden)
        #expect(stage.content.name == names(panel)[0])
        #expect(stage.content.primary == "Open")
        #expect(stage.content.secondary == StageView.Key(words: "Actions", caps: ["⌘", "K"]))

        press("down", in: panel)
        let second = names(panel)[1]
        #expect(stage.content.name == second)

        panel.launcher.toggleActions()
        #expect(stage.content.name == second, "⌘K keeps the item on the tile")
        #expect(stage.content.primary == "Open")
        #expect(stage.content.secondary == StageView.Key(words: "Back", caps: ["esc"]))
        press("down", in: panel)
        #expect(stage.content.primary == "Reveal in Finder", "the selected action is what ⏎ does")

        await type("gqqq", in: panel)
        #expect(stage.isHidden, "no rows, no tile")
    }

    /// The selection's fill is quiet, so the selected row also ends in ↩, and no other row does (decision 29).
    @Test func onlyTheSelectedRowEndsInReturn() async {
        let panel = makePanel(items: apps)
        func marked() -> [Int] {
            var rows: [Int] = []
            panel.launcher.tableView.enumerateAvailableRowViews { view, row in
                if (view.view(atColumn: 0) as? ResultCell)?.isSelected == true { rows.append(row) }
            }
            return rows
        }
        await type("g", in: panel)
        #expect(marked() == [0])
        press("down", in: panel)
        press("down", in: panel)
        #expect(marked() == [2])
    }

    @Test func theTileSplitsAProblemIntoTitleAndSentence() {
        let unknown = LauncherViewController.problemTile("line 3: unknown setting \"theme\"")
        #expect(unknown.title == "Config problem, line 3")
        #expect(unknown.detail == "Unknown setting \"theme\"")
        let named = LauncherViewController.problemTile("line 5: launcher.max_depth should be a number")
        #expect(named.detail == "launcher.max_depth should be a number", "a setting's name keeps its case")
    }

    @Test func saysWhenAnItemWasLastOpened() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 15)))
        func daysBefore(_ days: Int) throws -> Date {
            try #require(calendar.date(byAdding: .day, value: -days, to: now))
        }
        #expect(LauncherViewController.opened(now.addingTimeInterval(-3600), now: now).hasPrefix("opened today at "))
        #expect(LauncherViewController.opened(try daysBefore(1), now: now) == "opened yesterday")
        #expect(LauncherViewController.opened(try daysBefore(3), now: now) == "opened Tuesday")
        #expect(LauncherViewController.opened(try daysBefore(10), now: now) == "opened Nov 10")
    }

    @Test func searchFieldHasNoTextServices() throws {
        let panel = makePanel(items: apps)
        let editor = try #require(panel.fieldEditor(true, for: panel.launcher.searchField) as? NSTextView)
        #expect(editor.isFieldEditor)
        #expect(editor.inlinePredictionType == .no)
        #expect(editor.writingToolsBehavior == .none)
        #expect(!editor.isContinuousSpellCheckingEnabled)
        #expect(!editor.isAutomaticSpellingCorrectionEnabled)
        #expect(!editor.isAutomaticTextCompletionEnabled)
    }

    @Test func resetEmptiesAndCollapses() async {
        let panel = makePanel(items: apps)
        await type("g", in: panel)
        panel.launcher.reset()
        #expect(panel.launcher.searchField.stringValue.isEmpty)
        #expect(panel.launcher.rows.isEmpty)
        #expect(panel.frame.height == Layout.barHeight)
    }

    @Test func recentListsWhatWasOpenedNewestFirst() {
        let panel = makePanel(items: apps, opened: [apps[0].id, apps[2].id, "/gone/Old.app"], emptyState: .recent)
        panel.launcher.prepareToShow()
        #expect(names(panel.launcher.rows) == ["Widget", "Gizmo"], "items no longer in the index are skipped")
        #expect(panel.launcher.tableView.selectedRow == 0)
        #expect(panel.frame.height == Layout.expandedHeight)
    }

    @Test func recentWithoutHistoryIsJustTheSearchBar() {
        let panel = makePanel(items: apps, emptyState: .recent)
        panel.launcher.prepareToShow()
        #expect(panel.launcher.rows.isEmpty)
        #expect(panel.frame.height == Layout.barHeight)
    }

    @Test func runningListsOpenAppsThenAllOthersAlphabetically() {
        let commands = Command.allCases.map(Item.init(command:))
        let panel = makePanel(items: apps + commands, emptyState: .running)
        panel.launcher.prepareToShow()
        let running = RunningApps()
        let rows = panel.launcher.rows
        #expect(!running.order.isEmpty, "Finder at least is always running")
        #expect(rows.count == running.order.count + apps.count, "every open app, then every other app, no commands")
        #expect(
            Array(names(rows).suffix(apps.count)) == ["Gadget Pro", "Gizmo", "Hollow Thing", "Sprocket", "Widget"],
            "the made-up apps aren't running, so they come after, alphabetically")
        #expect(panel.launcher.tableView.selectedRow == (running.order.count > 1 ? 1 : 0))
    }

    @Test func problemsComeFirst() {
        let panel = makePanel(
            items: apps, opened: [apps[0].id], emptyState: .recent, problems: ["line 2: unknown setting x"])
        panel.launcher.prepareToShow()
        #expect(panel.launcher.rows == [.problem("line 2: unknown setting x"), .item(apps[0])])
        #expect(panel.launcher.tableView.selectedRow == 1)
    }

    @Test func historyBoostsWhatYouOpenMost() async {
        let panel = makePanel(items: apps, opened: Array(repeating: apps[2].id, count: 5))
        panel.launcher.prepareToShow()
        await type("g", in: panel)
        #expect(names(panel.launcher.rows).first == "Widget", "without history it would be Gizmo, the shortest")
    }

    @Test func commandsAreSearchable() async {
        let panel = makePanel(items: apps + Command.allCases.map(Item.init(command:)))
        panel.launcher.version = "0.3.0"
        await type("quit", in: panel)
        #expect(panel.launcher.rows.first == .item(Item(command: .quit)))
        #expect(panel.launcher.stage.content.kind == "Pith 0.3.0", "the version, for whoever tries a build")
    }

    @Test func cOrClipboardPutsClipboardHistoryFirstAndReturnOpensIt() async {
        let calendar = Item(name: "Calendar", appAt: URL(filePath: "/nonexistent/Calendar.app"))
        let panel = makePanel(items: apps + [calendar] + Command.allCases.map(Item.init(command:)))
        panel.launcher.clipboardHotkey = "⇧⌘V"
        for query in ["c", "clipboard"] {
            await type(query, in: panel)
            #expect(panel.launcher.rows.first == .item(Item(command: .clipboard)), "\(query)")
        }
        #expect(panel.launcher.stage.content.primary == "Open")
        #expect(panel.launcher.stage.content.kind == "Also ⇧⌘V, from any app")

        press("return", in: panel)
        #expect(panel.launcher.mode == .clipboard, "it opens in place")
        #expect(panel.launcher.searchField.stringValue.isEmpty)
    }

    /// The keypad's Enter (and fn+Return) does what Return does.
    @Test func keypadEnterIsReturn() async {
        let panel = makePanel(items: apps + Command.allCases.map(Item.init(command:)))
        var run: [Command] = []
        panel.launcher.runCommand = { run.append($0) }
        await type("quit pith", in: panel)
        let enter = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .numericPad, timestamp: 0,
            windowNumber: panel.windowNumber, context: nil, characters: "\u{3}", charactersIgnoringModifiers: "\u{3}",
            isARepeat: false, keyCode: UInt16(kVK_ANSI_KeypadEnter))!
        #expect(panel.handleKey(enter))
        #expect(run == [.quit])
    }

    @Test func clearClipboardHistoryWaitsForASecondReturn() async {
        let panel = makePanel(items: apps + Command.allCases.map(Item.init(command:)))
        var run: [Command] = []
        panel.launcher.runCommand = { run.append($0) }
        await type("clear clip", in: panel)
        #expect(panel.launcher.rows.first == .item(Item(command: .clearClipboard)))
        #expect(panel.launcher.stage.content.kind == "Pinned items stay")
        func title() -> String? {
            (panel.launcher.tableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? ResultCell)?
                .textField?.stringValue
        }

        press("return", in: panel)
        #expect(run.isEmpty)
        #expect(title() == "Press ⏎ again to clear the clipboard history")
        #expect(panel.launcher.stage.content.isDanger)
        #expect(panel.launcher.stage.content.secondary?.words == "Cancel")

        press("escape", in: panel)
        #expect(!panel.launcher.confirming && title() == "Clear Clipboard History", "⎋ cancels it")
        #expect(!panel.launcher.stage.content.isDanger)

        press("return", in: panel)
        press("return", in: panel)
        #expect(run == [.clearClipboard])
    }

    @Test func onlyTheRecordingCommandThatAppliesIsListed() async {
        let panel = makePanel(
            items: apps + Command.allCases.map(Item.init(command:)),
            opened: ["command:pause-clipboard", "command:resume-clipboard"], emptyState: .recent)
        await type("recording", in: panel)
        #expect(names(panel) == ["Pause Clipboard Recording"], "recording")

        panel.launcher.hiddenCommands = [.pauseClipboard]
        await type("recordin", in: panel)
        #expect(names(panel) == ["Resume Clipboard Recording"], "paused")
        await type("", in: panel)
        #expect(names(panel) == ["Resume Clipboard Recording"], "the recent list leaves it out too")
    }

    @Test func aReadyUpdateIsListedFirstAndReturnRestarts() async {
        let panel = makePanel(
            items: apps + Command.allCases.map(Item.init(command:)), opened: [apps[0].id, "command:install-update"],
            emptyState: .recent)
        var run: [Command] = []
        panel.launcher.runCommand = { run.append($0) }
        await type("update pith", in: panel)
        #expect(panel.launcher.rows.isEmpty, "nothing to install yet")

        panel.launcher.readyUpdate = "0.3.1"
        await type("", in: panel)
        #expect(names(panel) == ["Update Pith", "Gizmo"], "first, and not again as a recent item")
        #expect(panel.launcher.tableView.selectedRow == 1, "⏎ still opens what it did")
        press("up", in: panel)
        #expect(panel.launcher.stage.content.place == "Pith 0.3.1 is ready")
        #expect(panel.launcher.stage.content.primary == "Restart")
        press("return", in: panel)
        #expect(run == [.installUpdate])
    }

    @Test func updatesAreCheckedOnceADayAndAnHourAfterAFailure() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let hour: TimeInterval = 3_600
        var schedule = UpdateSchedule()
        // Hours after `start` that a check is attempted at, and whether it's due; a failure at hour 24.
        var due: [Bool] = []
        for (hours, failed) in [(0.0, false), (23, false), (24, true), (24.98, false), (25, false), (26, false)] {
            due.append(schedule.take(at: start + hours * hour))
            if failed { schedule.failed(at: start + hours * hour) }
        }
        #expect(due == [true, false, true, false, true, false], "first chance, a day later, an hour after a failure")
    }

    @Test func checkForUpdatesIsListedOnlyWhenItCanDoSomething() async {
        let panel = makePanel(items: apps + Command.allCases.map(Item.init(command:)))
        var run: [Command] = []
        panel.launcher.runCommand = { run.append($0) }
        panel.launcher.version = "0.3.2"
        await type("check for updates", in: panel)
        #expect(panel.launcher.rows.isEmpty, "a copy that doesn't update itself, like make run's")

        panel.launcher.checksForUpdates = true
        await type("check for updates", in: panel)
        #expect(names(panel) == ["Check for Updates"])
        #expect(panel.launcher.stage.content.kind == "Pith 0.3.2")
        #expect(panel.launcher.stage.content.primary == "Check")
        press("return", in: panel)
        #expect(run == [.checkForUpdates])

        panel.launcher.readyUpdate = "0.3.3"
        await type("check for updates", in: panel)
        #expect(panel.launcher.rows.isEmpty, "Update Pith is listed instead")
    }

    @Test func aCheckThatWasAskedForPutsTheNextADayLater() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let hour: TimeInterval = 3_600
        var schedule = UpdateSchedule()
        let first = schedule.take(at: start)
        schedule.takeNow(at: start + 5 * hour)
        let dayAfterTheFirst = schedule.take(at: start + 24 * hour)
        let dayAfterTheAsked = schedule.take(at: start + 29 * hour)
        #expect(first)
        #expect(!dayAfterTheFirst, "not due a day after the scheduled check")
        #expect(dayAfterTheAsked, "a day after the one asked for")
    }

    @Test func eachUpdateNotificationSaysWhatHappened() {
        let said = [
            UpdateResult.updated(to: "0.3.2"), .failed(to: "0.3.3", reason: "The update is improperly signed."),
            .ready("0.3.3"), .upToDate("0.3.2"),
            .checkFailed(reason: "A server with the specified hostname could not be found."),
        ].map { [$0.title, $0.body] }
        #expect(
            said == [
                ["Pith updated to 0.3.2", ""],
                ["Couldn't update Pith to 0.3.3", "The update is improperly signed."],
                ["Pith 0.3.3 is ready", "Update Pith in the launcher restarts into it."],
                ["Pith is up to date", "0.3.2 is the newest version."],
                ["Couldn't check for updates", "A server with the specified hostname could not be found."],
            ])
    }

    @Test func theLaunchAfterAnUpdateSaysHowItWent() {
        var ready = PendingUpdate(build: "202611231214", version: "0.3.1")
        #expect(ready.result(runningBuild: "202611231214", runningVersion: "0.3.1") == .updated(to: "0.3.1"))
        #expect(
            ready.result(runningBuild: "202611231210", runningVersion: "0.3.0") == nil,
            "not installed on quit: the next check finds it again")
        ready.requested = true
        #expect(
            ready.result(runningBuild: "202611231210", runningVersion: "0.3.0")
                == .failed(to: "0.3.1", reason: "Pith is still 0.3.0, and tries again on its next check."))
    }

    @Test func onlyAFoundUpdateThatFailsIsReported() {
        func sparkle(_ code: Int) -> NSError { NSError(domain: "SUSparkleErrorDomain", code: code) }
        #expect(!Updater.isUpdateProblem(sparkle(1002)), "the feed couldn't be read: offline, DNS")
        #expect(!Updater.isUpdateProblem(sparkle(1001)), "no update")
        #expect(Updater.isUpdateProblem(sparkle(2001)), "its download")
        #expect(Updater.isUpdateProblem(sparkle(3001)), "its signature")
        #expect(Updater.isUpdateProblem(sparkle(4005)), "its install")
        #expect(!Updater.isUpdateProblem(sparkle(4007)), "canceled")
        #expect(!Updater.isUpdateProblem(NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)))
    }

    @Test func sparklesOwnScheduleIsOffAndUpdatesDownloadOnTheirOwn() throws {
        // The Info.plist the app is built with: Pith asks for checks itself, with no timer (decision 48).
        let file = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Support/Info.plist")
        let plist = try #require(NSDictionary(contentsOf: file) as? [String: Any])
        #expect(plist["SUFeedURL"] as? String == "https://pith.edoardobertoli.xyz/appcast.xml")
        #expect(plist["SUEnableAutomaticChecks"] as? Bool == false)
        #expect(plist["SUAllowsAutomaticUpdates"] as? Bool == true, "else turning the schedule off stops downloads too")
        #expect(plist["SUAutomaticallyUpdate"] as? Bool == true)
        // The bundle names its icon, and make app copies it from Support (decision 54).
        #expect(plist["CFBundleIconFile"] as? String == "AppIcon")
        #expect(
            FileManager.default.fileExists(
                atPath: file.deletingLastPathComponent().appending(path: "AppIcon.icns").path))
    }

    @Test func commandKListsActionsAndEscapeGoesBack() async {
        let panel = makePanel(items: apps)
        await type("g", in: panel)
        press("down", in: panel)
        let results = panel.launcher.rows
        let selected = panel.launcher.tableView.selectedRow

        panel.launcher.toggleActions()
        #expect(names(panel) == ["Open", "Reveal in Finder"], "not running: no Quit")
        #expect(panel.launcher.searchField.stringValue.isEmpty)
        #expect(panel.launcher.searchField.placeholderString == "Filter actions")

        await type("rev", in: panel)
        #expect(names(panel) == ["Reveal in Finder"])

        press("escape", in: panel)
        #expect(panel.launcher.searchField.stringValue == "g")
        #expect(panel.launcher.rows == results)
        #expect(panel.launcher.tableView.selectedRow == selected)
    }

    @Test func forceQuitWaitsForASecondReturn() async throws {
        // Finder is always running, so it has Force Quit. Quitting is swapped out: nothing real is ever quit.
        let finder = Item(name: "Finder", appAt: URL(filePath: "/System/Library/CoreServices/Finder.app"))
        let panel = makePanel(items: [finder])
        var quits: [Bool] = []
        panel.launcher.quitApp = { _, force in quits.append(force) }
        await type("finder", in: panel)
        panel.launcher.toggleActions()
        try #require(panel.launcher.rows.last == .action(.forceQuit), "Finder isn't running")
        let last = panel.launcher.rows.count - 1
        for _ in 0..<last { press("down", in: panel) }
        func title() -> String? {
            (panel.launcher.tableView.view(atColumn: 0, row: last, makeIfNecessary: false) as? ResultCell)?
                .textField?.stringValue
        }

        press("return", in: panel)
        #expect(quits.isEmpty)
        #expect(title() == "Press ⏎ again to force quit Finder")
        #expect(panel.launcher.stage.content.isDanger)
        #expect(panel.launcher.stage.content.secondary?.words == "Cancel")

        press("escape", in: panel)
        #expect(panel.launcher.sublist != nil, "⎋ cancels the confirmation, not the actions")
        #expect(title() == "Force Quit")

        press("return", in: panel)
        press("up", in: panel)
        press("down", in: panel)
        #expect(!panel.launcher.confirming, "moving the selection cancels it too")

        press("return", in: panel)
        press("return", in: panel)
        #expect(quits == [true])
    }

    @Test func eightRowsFitAndShareTheBarsGrid() async throws {
        let many = (1...12).map { Item(name: "Gizmo \($0)", appAt: URL(filePath: "/nonexistent/Gizmo \($0).app")) }
        let panel = makePanel(items: many)
        await type("gizmo", in: panel)
        let root = try #require(panel.contentView)
        let table = panel.launcher.tableView

        let eighth = table.convert(table.rect(ofRow: 7), to: root)
        #expect(
            eighth.maxY == Layout.expandedHeight - Layout.listBottomInset,
            "the 8th row ends where the panel's inset starts")
        #expect(table.rect(ofRow: 0).width == Layout.width, "a scrolling list keeps its full width")

        let cell = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: false) as? ResultCell)
        cell.layoutSubtreeIfNeeded()
        let icon = cell.icon.convert(cell.icon.bounds, to: root)
        let magnifier = try #require(root.subviews.first { $0 is NSImageView })
        #expect(magnifier.frame.midX == icon.midX, "the magnifier sits on the icons' column")
        let title = try #require(cell.textField)
        #expect(title.convert(title.bounds, to: root).minX == panel.launcher.searchField.frame.minX)
    }

    @Test func commandKDoesNothingForCommands() async {
        let panel = makePanel(items: [Item(command: .quit)])
        await type("quit", in: panel)
        panel.launcher.toggleActions()
        #expect(panel.launcher.rows == [.item(Item(command: .quit))])
    }

    @Test func filesShowUpMergedWithTheirFolder() async throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("Reports/Quarterly Gizmo.pdf")
        let files = FileSearchEngine()
        await files.rebuild(FileRules(roots: [folder.url.path], ignore: IgnoreRules([]), maxDepth: 6))
        let panel = makePanel(items: apps, files: files)

        await type("gizmo", in: panel)
        #expect(
            names(panel.launcher.rows) == ["Gizmo", "Quarterly Gizmo.pdf"], "the app first: same match, head start")
        let cell = try #require(
            panel.launcher.tableView.view(atColumn: 0, row: 1, makeIfNecessary: false) as? ResultCell)
        cell.layoutSubtreeIfNeeded()
        let title = try #require(cell.textField)
        let detail = try #require(cell.subviews.compactMap { $0 as? NSTextField }.first { $0 !== title })
        #expect(cell.detail.hasSuffix("/Reports"))
        #expect(detail.frame.minX > title.frame.maxX, "the folder follows the name")
        #expect(abs(detail.frame.midY - title.frame.midY) < 3, "on the same line")

        await type("quarterly", in: panel)
        #expect(
            panel.launcher.rows == [
                .item(Item(path: folder.url.path + "/Reports/Quarterly Gizmo.pdf", isFolder: false))
            ])
    }

    @Test func recentListsFilesToo() {
        let panel = makePanel(items: apps, opened: [apps[0].id, "folder:/tmp/Somewhere"], emptyState: .recent)
        panel.launcher.prepareToShow()
        #expect(panel.launcher.rows == [.item(Item(path: "/tmp/Somewhere", isFolder: true)), .item(apps[0])])
    }

    @Test func commandKOnAFileOffersNoQuit() async throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("notes.md")
        let files = FileSearchEngine()
        await files.rebuild(FileRules(roots: [folder.url.path], ignore: IgnoreRules([]), maxDepth: 6))
        let panel = makePanel(items: [], files: files)
        await type("notes", in: panel)
        panel.launcher.toggleActions()
        #expect(
            names(panel) == [
                "Open", "Reveal in Finder", "Copy Path", "Open With…", "Copy File", "Zip", "Move to Trash",
            ])
    }

    /// A Move to Trash that fails says so (decision 32), and the file stays in the history. The file doesn't exist, so
    /// nothing ever reaches the Trash.
    @Test func aFailedMoveToTrashIsReported() async throws {
        let folder = try TemporaryDirectory()
        let missing = Item(path: folder.url.appending(path: "Quarterly_Budget_Review.pdf").path, isFolder: false)
        let panel = makePanel(items: [], opened: [missing.id], emptyState: .recent)
        var failures: [String] = []
        panel.launcher.reportFailure = { title, _, _ in failures.append(title) }
        panel.launcher.prepareToShow()
        panel.launcher.toggleActions()
        try #require(panel.launcher.rows.last == .action(.trash))
        for _ in 1..<panel.launcher.rows.count { press("down", in: panel) }

        press("return", in: panel)
        #expect(await eventually { !failures.isEmpty })
        #expect(failures == ["Couldn't move Quarterly_Budget_Review.pdf to the Trash"])
        panel.launcher.reset()
        panel.launcher.prepareToShow()
        #expect(names(panel) == ["Quarterly_Budget_Review.pdf"], "still in the recent list")
    }

    @Test func commandKOnAFolderOffersTerminal() async throws {
        let folder = try TemporaryDirectory()
        try folder.makeFolder("Projects Zeta")
        let files = FileSearchEngine()
        await files.rebuild(FileRules(roots: [folder.url.path], ignore: IgnoreRules([]), maxDepth: 6))
        let panel = makePanel(items: [], files: files)
        await type("zeta", in: panel)
        panel.launcher.toggleActions()
        #expect(
            names(panel) == [
                "Open in Finder", "Reveal in Finder", "Copy Path", "Open in Terminal", "Copy Folder", "Zip",
                "Move to Trash",
            ])
    }

    @Test func openWithListsAppsAndEscapeStepsBack() async throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("letter.txt")
        let files = FileSearchEngine()
        await files.rebuild(FileRules(roots: [folder.url.path], ignore: IgnoreRules([]), maxDepth: 6))
        let panel = makePanel(items: [], files: files)
        await type("letter", in: panel)
        panel.launcher.toggleActions()
        await type("with", in: panel)
        #expect(names(panel) == ["Open With…"])
        press("return", in: panel)

        #expect(await eventually { if case .openWith? = panel.launcher.sublist { true } else { false } })
        #expect(names(panel).contains("TextEdit"), "\(names(panel))")
        #expect(panel.launcher.searchField.placeholderString == "Filter apps")
        #expect(panel.launcher.stage.content.name == "letter.txt", "the file stays on the tile")
        #expect(panel.launcher.stage.content.primary.hasPrefix("Open in "))

        press("escape", in: panel)
        #expect(names(panel) == ["Open With…"], "back to the actions, still filtered")
        #expect(panel.launcher.searchField.stringValue == "with")
        press("escape", in: panel)
        #expect(panel.launcher.sublist == nil)
        #expect(panel.launcher.searchField.stringValue == "letter")
    }

    @Test func previewsFilesAndFoldersOnly() async throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("Gizmo manual.pdf")
        let files = FileSearchEngine()
        await files.rebuild(FileRules(roots: [folder.url.path], ignore: IgnoreRules([]), maxDepth: 6))
        let panel = makePanel(items: apps, files: files)

        await type("gizmo", in: panel)
        #expect(panel.launcher.previewURL == nil, "the app Gizmo is selected")
        press("down", in: panel)
        #expect(panel.launcher.previewURL?.lastPathComponent == "Gizmo manual.pdf")
        panel.launcher.toggleActions()
        #expect(panel.launcher.previewURL == nil, "not from the actions list")
    }

    @Test func everySymbolExists() {
        for name in Symbols.all {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }
}

struct RunningAppsTests {
    @Test func runningAppsHaveTheIdsTheIndexUses() throws {
        let index = SearchIndex(items: AppScanner.scan(AppScanner.defaultRoots, extras: AppScanner.defaultExtras))
        let running = RunningApps()
        let finder = try #require(running.order.first { $0.hasSuffix("/Finder.app") }, "Finder is always running")
        #expect(index.position(of: finder) != nil)
        let indexed = running.order.filter { $0.hasPrefix("/Applications/") || $0.hasPrefix("/System/Applications/") }
        #expect(indexed.allSatisfy { index.position(of: $0) != nil }, "\(indexed)")
    }
}

extension RunningAppsTests {
    @Test func syncMatchesWhatMacOSReportsAndIsStable() {
        let running = RunningApps()
        let open = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && !$0.isTerminated }
                .compactMap { $0.bundleURL?.resolvingSymlinksInPath().path })
        #expect(Set(running.order) == open)
        #expect(running.order.allSatisfy { running.application($0)?.isTerminated == false })
        #expect(!running.sync(), "nothing changed, so nothing to report")
    }
}

/// The keys from `[keys]` (decision 55), pressed as the keyboard would.
struct PanelKeysTests {
    private func bindings(_ text: String) -> KeyBindings {
        let (config, problems) = Config.parse(text)
        #expect(problems.isEmpty)
        return config.keys
    }

    @Test func reboundKeysReplaceTheDefaults() async {
        let panel = makePanel(items: apps)
        panel.launcher.keys = bindings("[keys]\ndown = \"ctrl+n\"\nopen = \"cmd+return\"")
        await type("g", in: panel)
        #expect(!press("down", in: panel), "↓ goes on to the field")
        #expect(panel.launcher.tableView.selectedRow == 0)
        #expect(press("ctrl+n", in: panel))
        #expect(panel.launcher.tableView.selectedRow == 1)
        #expect(press("ctrl+k", in: panel), "up keeps its defaults")
        #expect(panel.launcher.tableView.selectedRow == 0)
    }

    @Test func aKeyThatTypesActsOnlyOnAnEmptyField() async {
        let panel = makePanel(items: apps, emptyState: .running)
        panel.launcher.keys = bindings("[keys]\ndown = [\"down\", \"j\"]")
        panel.launcher.prepareToShow()
        let selected = panel.launcher.tableView.selectedRow
        #expect(press("j", in: panel))
        #expect(panel.launcher.tableView.selectedRow == selected + 1)
        await type("g", in: panel)
        #expect(!press("j", in: panel), "with a query, j is a letter")
        #expect(!press("space", in: panel), "and Space a space, with no file to preview")
    }

    @Test func theTileAndRowsShowTheKeysAsConfigured() async {
        let panel = makePanel(items: apps)
        panel.launcher.keys = bindings(
            "[keys]\nopen = \"cmd+return\"\nactions = \"cmd+.\"\nback = \"ctrl+g\"\nrun_actions = [\"ctrl+1\"]")
        let stage = panel.launcher.stage
        await type("g", in: panel)
        #expect(stage.openCaps == ["⌘", "↩"])
        #expect(stage.content.secondary == StageView.Key(words: "Actions", caps: ["⌘", "."]))
        func cells() -> [ResultCell] {
            var cells: [ResultCell] = []
            panel.launcher.tableView.enumerateAvailableRowViews { view, _ in
                if let cell = view.view(atColumn: 0) as? ResultCell { cells.append(cell) }
            }
            return cells
        }
        #expect(cells().first?.openKey == "⌘↩", "the selected row ends in open's key")

        #expect(press("cmd+.", in: panel))
        #expect(stage.content.secondary == StageView.Key(words: "Back", caps: ["⌃", "G"]))
        #expect(cells().map(\.trailingTag) == ["⌃1", ""], "Open and Reveal: only the actions with a key show one")
        #expect(press("ctrl+g", in: panel))
        #expect(panel.launcher.sublist == nil)
    }

    @Test func turnedOffActionsShowNoKey() async {
        let panel = makePanel(items: apps)
        panel.launcher.keys = bindings("[keys]\nactions = []")
        await type("g", in: panel)
        #expect(panel.launcher.stage.content.secondary == nil)
        #expect(!press("cmd+k", in: panel))
        #expect(panel.launcher.sublist == nil)
    }

    @Test func theClipboardAliasIsConfigurable() async {
        let panel = makePanel(items: apps + [Item(command: .clipboard)])
        panel.launcher.clipboardAlias = "v"
        await type("v", in: panel)
        #expect(names(panel).first == "Clipboard History")
        await type("c ", in: panel)
        #expect(panel.launcher.mode == .launcher, "c is just a letter now")
        await type("v ", in: panel)
        #expect(panel.launcher.mode == .clipboard)
    }
}
