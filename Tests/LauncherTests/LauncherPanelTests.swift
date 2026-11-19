import AppKit
import LauncherCore
import Testing

@testable import Launcher

/// A real panel, laid out and drawn but never ordered onto the screen. Its history lives in a temporary file and
/// starts with `opened`, oldest first.
func makePanel(
    items: [Item], opened: [String] = [], emptyState: Config.EmptyState = .none, problems: [String] = []
) -> LauncherPanel {
    _ = NSApplication.shared
    let history = HistoryStore(
        file: FileManager.default.temporaryDirectory.appending(path: "LauncherTests-\(UUID().uuidString).json"))
    for id in opened { history.record(id) }
    let launcher = LauncherViewController(history: history, running: RunningApps())
    launcher.emptyState = emptyState
    launcher.problems = problems
    let panel = LauncherPanel(launcher: launcher)
    launcher.index = SearchIndex(items: items)
    return panel
}

func type(_ text: String, in panel: LauncherPanel) {
    panel.launcher.searchField.stringValue = text
    panel.launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    panel.layoutIfNeeded()
}

func press(_ command: Selector, in panel: LauncherPanel) {
    _ = panel.launcher.control(panel.launcher.searchField, textView: NSTextView(), doCommandBy: command)
}

/// Made-up apps, so none of them is running on the machine that runs the tests.
private let apps = ["Gizmo", "Gadget Pro", "Widget", "Hollow Thing", "Sprocket"].map {
    Item(name: $0, appAt: URL(filePath: "/nonexistent/\($0).app"))
}

private func names(_ rows: [Row]) -> [String] {
    rows.map {
        switch $0 {
        case .item(let item): item.name
        case .action(let action): action.title
        case .problem(let message): message
        }
    }
}

struct LauncherPanelTests {
    @Test func opensAsJustTheSearchBarWhenTheEmptyStateIsNone() {
        let panel = makePanel(items: apps, opened: [apps[0].id])
        panel.launcher.prepareToShow()
        #expect(panel.launcher.rows.isEmpty)
        #expect(panel.frame.height == Layout.barHeight)
    }

    @Test func growsWithResultsAndShrinksKeepingTheTopEdge() {
        let panel = makePanel(items: apps)
        let top = panel.frame.maxY

        type("g", in: panel)
        #expect(panel.frame.height == Layout.expandedHeight)
        #expect(panel.frame.maxY == top)

        type("gqqq", in: panel)
        #expect(panel.frame.height == Layout.barHeight)
        #expect(panel.frame.maxY == top)
    }

    @Test func namesUseTheWholeRow() throws {
        let panel = makePanel(items: apps)
        type("giz", in: panel)
        let cell = try #require(
            panel.launcher.tableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? ResultCell)
        let title = try #require(cell.textField)
        #expect(title.stringValue == "Gizmo")
        #expect(cell.frame.width > Layout.width - 60, "the column spans the table")
        #expect(title.frame.width > Layout.width - 120, "the title spans the cell")
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

    @Test func resetEmptiesAndCollapses() {
        let panel = makePanel(items: apps)
        type("g", in: panel)
        panel.launcher.reset()
        #expect(panel.launcher.searchField.stringValue.isEmpty)
        #expect(panel.launcher.tableView.numberOfRows == 0)
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

    @Test func historyBoostsWhatYouOpenMost() {
        let panel = makePanel(items: apps, opened: Array(repeating: apps[2].id, count: 5))
        panel.launcher.prepareToShow()
        type("g", in: panel)
        #expect(names(panel.launcher.rows).first == "Widget", "without history it would be Gizmo, the shortest")
    }

    @Test func commandsAreSearchable() {
        let panel = makePanel(items: apps + Command.allCases.map(Item.init(command:)))
        type("quit", in: panel)
        #expect(panel.launcher.rows.first == .item(Item(command: .quit)))
    }

    @Test func commandKListsActionsAndEscapeGoesBack() {
        let panel = makePanel(items: apps)
        type("g", in: panel)
        press(#selector(NSResponder.moveDown(_:)), in: panel)
        let results = panel.launcher.rows
        let selected = panel.launcher.tableView.selectedRow

        panel.launcher.toggleActions()
        #expect(names(panel.launcher.rows) == ["Open", "Reveal in Finder"], "not running: no Quit")
        #expect(panel.launcher.searchField.stringValue.isEmpty)
        #expect(panel.launcher.searchField.placeholderString?.hasPrefix("Actions for ") == true)

        type("rev", in: panel)
        #expect(names(panel.launcher.rows) == ["Reveal in Finder"])

        press(#selector(NSResponder.cancelOperation(_:)), in: panel)
        #expect(panel.launcher.searchField.stringValue == "g")
        #expect(panel.launcher.rows == results)
        #expect(panel.launcher.tableView.selectedRow == selected)
    }

    @Test func commandKDoesNothingForCommands() {
        let panel = makePanel(items: [Item(command: .quit)])
        type("quit", in: panel)
        panel.launcher.toggleActions()
        #expect(panel.launcher.rows == [.item(Item(command: .quit))])
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
