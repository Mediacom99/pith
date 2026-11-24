import AppKit
import LauncherCore
import TestSupport
import Testing

@testable import Launcher

/// Quick Look in place of the real one: it records what the launcher asks of it, and nothing goes on screen.
final class FakePreviewPanel: PreviewPanel {
    private(set) var isVisible = false
    private(set) var reloads = 0

    func show(above window: NSWindow) {
        isVisible = true
        reloads += 1
    }

    func reloadData() { reloads += 1 }
    func orderOut(_ sender: Any?) { isVisible = false }
}

/// A panel that counts as on screen, with two files found, a fake Quick Look and no global monitor: `clickElsewhere`
/// stands in for a click in another app, and `dismissals` counts the closes.
final class FocusHarness {
    let panel: LauncherPanel
    let quickLook = FakePreviewPanel()
    let folder: TemporaryDirectory
    private(set) var dismissals = 0
    private(set) var isWatchingClicks = false
    private var shown = true
    private var clicked: (@MainActor () -> Void)?

    init() async throws {
        folder = try TemporaryDirectory()
        try folder.makeFile("Acme brief.pdf")
        try folder.makeFile("Acme budget.pdf")
        let files = FileSearchEngine()
        await files.rebuild(FileRules(roots: [folder.url.path], ignore: IgnoreRules([]), maxDepth: 6))
        panel = makePanel(items: [], files: files)
        panel.isShown = { [unowned self] in shown }
        panel.onDismiss = { [unowned self] in
            dismissals += 1
            shown = false
        }
        panel.watchClicksElsewhere = { [unowned self] handler in
            clicked = handler
            isWatchingClicks = true
            return "monitor"
        }
        panel.stopWatchingClicks = { [unowned self] _ in
            clicked = nil
            isWatchingClicks = false
        }
        panel.launcher.previewPanel = { [quickLook] _ in quickLook }
        await type("acme", in: panel)
    }

    var previewing: String? { panel.launcher.previewing?.lastPathComponent }

    func clickElsewhere() { clicked?() }
}

/// The panel's focus rules around Quick Look, which can't be watched on screen in a test: what closes the panel, and
/// what mustn't. `docs/RELEASING.md` has the checks on the real windows.
@MainActor
struct PanelFocusTests {
    /// A press can reach the panel twice, as a key equivalent and then as a key: it toggles the preview once.
    @Test func onePressTogglesThePreviewOnce() async throws {
        let focus = try await FocusHarness()
        let press = keyEvent("cmd+y", in: focus.panel)
        #expect(focus.panel.handleKey(press))
        #expect(focus.panel.handleKey(press))
        #expect(focus.quickLook.isVisible)
        #expect(focus.previewing == "Acme brief.pdf")
        #expect(focus.quickLook.reloads == 1)
        #expect(focus.isWatchingClicks)

        #expect(focus.panel.handleKey(keyEvent("cmd+y", in: focus.panel)), "a new press")
        #expect(!focus.quickLook.isVisible)
        #expect(focus.previewing == nil)
        #expect(focus.dismissals == 0, "closing the preview leaves the launcher open")
    }

    /// ↓ moves the selection and the preview follows; the panel keeps the keyboard throughout.
    @Test func theArrowsMoveThePreview() async throws {
        let focus = try await FocusHarness()
        press("cmd+y", in: focus.panel)
        press("down", in: focus.panel)
        #expect(focus.previewing == "Acme budget.pdf")
        #expect(focus.quickLook.isVisible)
        press("up", in: focus.panel)
        #expect(focus.previewing == "Acme brief.pdf")
        #expect(focus.quickLook.reloads == 3)
    }

    /// 0.3.7's broken ⌘Y: Quick Look takes the keyboard as it opens, and losing it then mustn't close the launcher.
    /// Without the preview, losing the keyboard closes it.
    @Test func losingTheKeyboardToThePreviewKeepsThePanel() async throws {
        let focus = try await FocusHarness()
        press("cmd+y", in: focus.panel)
        focus.panel.resignKey()
        #expect(focus.dismissals == 0)
        #expect(focus.quickLook.isVisible)
        #expect(!focus.panel.launcher.rows.isEmpty)

        press("cmd+y", in: focus.panel)
        focus.panel.resignKey()
        #expect(focus.dismissals == 1)
        #expect(focus.panel.launcher.rows.isEmpty, "emptied for next time")
    }

    /// With the preview up, a click in another app closes both, and the click monitor goes with them.
    @Test func aClickInAnotherAppClosesBoth() async throws {
        let focus = try await FocusHarness()
        press("cmd+y", in: focus.panel)
        focus.clickElsewhere()
        #expect(focus.dismissals == 1)
        #expect(!focus.quickLook.isVisible)
        #expect(focus.previewing == nil)
        #expect(!focus.isWatchingClicks)
    }

    /// With the preview up, another app coming to the front (⌘Tab) closes both; Pith itself coming to the front doesn't.
    @Test func anotherAppComingToTheFrontClosesBoth() async throws {
        let focus = try await FocusHarness()
        focus.panel.appActivated(1)
        #expect(focus.dismissals == 0, "without the preview, losing the keyboard closes the panel instead")

        press("cmd+y", in: focus.panel)
        focus.panel.appActivated(ProcessInfo.processInfo.processIdentifier)
        #expect(focus.dismissals == 0)
        focus.panel.appActivated(1)
        #expect(focus.dismissals == 1)
        #expect(!focus.quickLook.isVisible)
    }

    /// ⎋ closes the preview first, then the launcher.
    @Test func escapeClosesThePreviewFirst() async throws {
        let focus = try await FocusHarness()
        press("cmd+y", in: focus.panel)
        press("escape", in: focus.panel)
        #expect(!focus.quickLook.isVisible)
        #expect(focus.dismissals == 0)
        press("escape", in: focus.panel)
        #expect(focus.dismissals == 1)
    }
}
