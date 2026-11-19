import AppKit
import LauncherCore
import Testing

@testable import Launcher

/// A real panel, laid out and drawn but never ordered onto the screen.
func makePanel(apps: [AppItem]) -> LauncherPanel {
    _ = NSApplication.shared
    let panel = LauncherPanel()
    panel.launcher.index = AppIndex(apps: apps)
    return panel
}

func type(_ text: String, in panel: LauncherPanel) {
    panel.launcher.searchField.stringValue = text
    panel.launcher.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
    panel.layoutIfNeeded()
}

private let apps = ["Ghostty", "Google Chrome", "Logi Options+", "Hollow Knight", "Safari"].map {
    AppItem(name: $0, url: URL(filePath: "/Applications/\($0).app"))
}

struct LauncherPanelTests {
    @Test func opensAsJustTheSearchBar() {
        let panel = makePanel(apps: apps)
        #expect(panel.frame.height == Layout.barHeight)
    }

    @Test func growsWithResultsAndShrinksWithoutKeepingTheTopEdge() {
        let panel = makePanel(apps: apps)
        let top = panel.frame.maxY

        type("g", in: panel)
        #expect(panel.frame.height == Layout.expandedHeight)
        #expect(panel.frame.maxY == top)

        type("gqqq", in: panel)
        #expect(panel.frame.height == Layout.barHeight)
        #expect(panel.frame.maxY == top)
    }

    @Test func namesUseTheWholeRow() throws {
        let panel = makePanel(apps: apps)
        type("gh", in: panel)
        let cell = try #require(
            panel.launcher.tableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? ResultCell)
        let title = try #require(cell.textField)
        #expect(title.stringValue == "Ghostty")
        #expect(cell.frame.width > Layout.width - 60, "the column spans the table")
        #expect(title.frame.width > Layout.width - 120, "the title spans the cell")
    }

    @Test func searchFieldHasNoTextServices() throws {
        let panel = makePanel(apps: apps)
        let editor = try #require(panel.fieldEditor(true, for: panel.launcher.searchField) as? NSTextView)
        #expect(editor.isFieldEditor)
        #expect(editor.inlinePredictionType == .no)
        #expect(editor.writingToolsBehavior == .none)
        #expect(!editor.isContinuousSpellCheckingEnabled)
        #expect(!editor.isAutomaticSpellingCorrectionEnabled)
        #expect(!editor.isAutomaticTextCompletionEnabled)
    }

    @Test func resetEmptiesAndCollapses() {
        let panel = makePanel(apps: apps)
        type("g", in: panel)
        panel.launcher.reset()
        #expect(panel.launcher.searchField.stringValue.isEmpty)
        #expect(panel.launcher.tableView.numberOfRows == 0)
        #expect(panel.frame.height == Layout.barHeight)
    }
}
