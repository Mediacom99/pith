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
