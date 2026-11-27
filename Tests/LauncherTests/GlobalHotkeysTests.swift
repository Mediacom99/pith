import Carbon.HIToolbox
import LauncherCore
import Testing

@testable import Launcher

/// Real global hotkeys, on F18 and F19 with every modifier: keys no app or person uses, taken only while a test runs.
@MainActor
struct GlobalHotkeysTests {
    let first = Shortcut("ctrl+alt+shift+cmd+f18")!
    let second = Shortcut("ctrl+alt+shift+cmd+f19")!

    @Test func twoHotkeysCanSwapKeys() {
        let hotkeys = GlobalHotkeys()
        hotkeys.apply([("launcher", first, { _ in }), ("clipboard", second, { _ in })])
        #expect(hotkeys.current("launcher") == first && hotkeys.current("clipboard") == second)
        #expect(hotkeys.problems.isEmpty)

        hotkeys.apply([("launcher", second, { _ in }), ("clipboard", first, { _ in })])
        #expect(hotkeys.current("launcher") == second && hotkeys.current("clipboard") == first)
        #expect(hotkeys.problems.isEmpty, "each was let go before the other took it")

        hotkeys.apply([("launcher", first, { _ in }), ("clipboard", nil, { _ in })])
        #expect(hotkeys.current("launcher") == first && hotkeys.current("clipboard") == nil)
        #expect(hotkeys.problems.isEmpty)
    }

    @Test func aTakenKeyKeepsTheOldOneUntilItsChangedBack() throws {
        let other = HotKeyCenter()
        _ = try #require(other.register(second) { _ in }, "another app holds it")
        let hotkeys = GlobalHotkeys()
        hotkeys.apply([("launcher", first, { _ in })])

        hotkeys.apply([("launcher", second, { _ in })])
        #expect(hotkeys.current("launcher") == first)
        #expect(
            hotkeys.problems == [
                "hotkeys.launcher \"ctrl+alt+shift+cmd+f19\" is taken by another app, so it's still \"ctrl+alt+shift+cmd+f18\""
            ])

        hotkeys.apply([("launcher", first, { _ in })])
        #expect(hotkeys.current("launcher") == first)
        #expect(hotkeys.problems.isEmpty, "back on its own key: the problem is gone")
    }

    /// A key macOS uses (⌘Space for Spotlight) registers, but never fires: it's taken, and the old key stays.
    @Test func aMacOSShortcutIsTaken() {
        let hotkeys = GlobalHotkeys(isSystemShortcut: { [second] in $0 == second })
        hotkeys.apply([("launcher", first, { _ in })])
        hotkeys.apply([("launcher", second, { _ in })])
        #expect(hotkeys.current("launcher") == first)
        #expect(
            hotkeys.problems == [
                "hotkeys.launcher \"ctrl+alt+shift+cmd+f19\" is taken by macOS (System Settings, Keyboard, Keyboard Shortcuts), so it's still \"ctrl+alt+shift+cmd+f18\""
            ])
        #expect(HotKeyCenter.isSystemShortcut(Shortcut("cmd+p")!) == false, "⌘P is no macOS shortcut")
    }

    /// A keyboard layout change registers every hotkey again, and says so, so the problems and the keys shown follow.
    @Test func aLayoutChangeRegistersThemAllAgain() {
        let hotkeys = GlobalHotkeys()
        var changes = 0
        hotkeys.onLayoutChange = { changes += 1 }
        hotkeys.apply([("launcher", first, { _ in }), ("clipboard", second, { _ in })])
        hotkeys.layoutChanged()
        #expect(hotkeys.current("launcher") == first && hotkeys.current("clipboard") == second)
        #expect(hotkeys.problems.isEmpty && changes == 1)
    }

    /// A scheduled check that fails on the same update again says nothing more; one that was asked for always says.
    @Test func aFailedUpdateIsSaidOnce() {
        var failures = UpdateFailures()
        let first = failures.shouldSay("0.4.0", asked: false)
        let again = failures.shouldSay("0.4.0", asked: false)
        let asked = failures.shouldSay("0.4.0", asked: true)
        let newer = failures.shouldSay("0.4.1", asked: false)
        #expect(first && !again && asked)
        #expect(newer, "a new version is news")
    }
}

/// The keys of the layout in use, whatever it is on the Mac running the tests.
@MainActor
struct KeyLayoutTests {
    @Test func everyLetterHasItsOwnKey() {
        let codes = "abcdefghijklmnopqrstuvwxyz".map { KeyLayout.keyCode(typing: String($0)) }
        #expect(!codes.contains(nil))
        #expect(Set(codes).count == 26)
    }

    @Test func keysThatDontTypeKeepTheirPlace() {
        #expect(KeyLayout.keyCode(of: Shortcut("cmd+up")!) == UInt32(kVK_UpArrow))
        #expect(KeyLayout.keyCode(of: Shortcut("f19")!) == UInt32(kVK_F19))
    }
}
