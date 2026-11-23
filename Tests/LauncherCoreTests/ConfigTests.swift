import Carbon.HIToolbox
import Testing

@testable import LauncherCore

struct ConfigTests {
    @Test func templateIsTheDefaults() {
        let (config, problems) = Config.parse(Config.template)
        #expect(problems.isEmpty)
        #expect(config == Config())
    }

    @Test func emptyFileIsTheDefaults() {
        let (config, problems) = Config.parse("")
        #expect(problems.isEmpty)
        #expect(config.launcherHotkey.description == "cmd+p")
        #expect(config.clipboardHotkey.description == "shift+cmd+v", "the modifiers in macOS order")
        #expect(config.emptyState == .recent)
        #expect(config.launchAtLogin)
    }

    @Test func readsEverySetting() {
        let (config, problems) = Config.parse(
            """
            [hotkeys]
            launcher = "ctrl+alt+space"   # a comment
            [launcher]
            empty_state = 'running'
            launch_at_login = false
            """)
        #expect(problems.isEmpty)
        #expect(config.launcherHotkey.description == "ctrl+alt+space")
        #expect(config.emptyState == .running)
        #expect(!config.launchAtLogin)
    }

    @Test func dottedKeysWork() {
        let (config, problems) = Config.parse("launcher.empty_state = \"none\"")
        #expect(problems.isEmpty)
        #expect(config.emptyState == .none)
    }

    @Test func badSettingsKeepTheirDefaultAndReportTheLine() {
        let (config, problems) = Config.parse(
            """
            [launcher]
            empty_state = "everything"
            launch_at_login = "yes"
            colour = "blue"
            [hotkeys]
            launcher = "p"
            """)
        #expect(config == Config())
        #expect(
            problems == [
                "line 2: launcher.empty_state is \"everything\", expected \"recent\", \"running\" or \"none\"",
                "line 3: launcher.launch_at_login should be true or false",
                "line 4: unknown setting \"launcher.colour\"",
                "line 6: hotkeys.launcher \"p\" isn't a shortcut like \"cmd+p\"",
            ])
    }

    @Test func invalidTOMLGivesTheDefaultsAndOneProblem() {
        let (config, problems) = Config.parse("[launcher]\nempty_state = \"recent\nlaunch_at_login = true")
        #expect(config == Config())
        #expect(problems == ["line 2: unterminated string, so every setting is at its default"])
    }
}

struct TOMLReaderTests {
    private func values(_ text: String) throws -> [String: [String: TOMLValue]] {
        try TOMLReader.parse(text).mapValues { $0.mapValues(\.value) }
    }

    @Test func readsTheSupportedValues() throws {
        let tables = try values(
            """
            name = "a \\"quoted\\" \\u00e9 word"
            literal = 'C:\\path'
            count = 1_000
            negative = -3
            ratio = 0.5
            on = true
            list = [
              "one",  # first
              "two",
            ]
            "quoted key" = 1
            """)
        #expect(tables[""]?["name"] == .string("a \"quoted\" é word"))
        #expect(tables[""]?["literal"] == .string("C:\\path"))
        #expect(tables[""]?["count"] == .integer(1000))
        #expect(tables[""]?["negative"] == .integer(-3))
        #expect(tables[""]?["ratio"] == .float(0.5))
        #expect(tables[""]?["on"] == .boolean(true))
        #expect(tables[""]?["list"] == .array([.string("one"), .string("two")]))
        #expect(tables[""]?["quoted key"] == .integer(1))
    }

    @Test func readsTablesAndDottedNames() throws {
        let tables = try values("[a.b]\nx = 1\n[c]\ny.z = 2\n")
        #expect(tables["a.b"]?["x"] == .integer(1))
        #expect(tables["c.y"]?["z"] == .integer(2))
    }

    @Test(arguments: [
        ("x = 1\nx = 2", "line 2: x is set twice"),
        ("[a]\n[a]", "line 2: table [a] is defined twice"),
        ("x = \"\"\"long\"\"\"", "line 1: multi-line strings aren't supported"),
        ("x = {a = 1}", "line 1: inline tables aren't supported"),
        ("[[items]]", "line 1: arrays of tables ([[…]]) aren't supported"),
        ("x = 1979-05-27", "line 1: 1979-05-27 isn't a number this reader supports"),
        ("x = 1 y = 2", "line 1: unexpected text after the value"),
        ("x = nope", "line 1: expected a value"),
        ("\n\nx = \"open", "line 3: unterminated string"),
        ("x = \"\\q\"", "line 1: unknown escape \\q"),
    ])
    func reportsErrorsWithTheirLine(text: String, message: String) {
        #expect(throws: TOMLError.self) { try TOMLReader.parse(text) }
        do {
            _ = try TOMLReader.parse(text)
        } catch {
            #expect(error.description == message)
        }
    }
}

struct HotkeyTests {
    @Test func readsShortcuts() throws {
        let hotkey = try #require(Hotkey("cmd+p"))
        #expect(hotkey.keyCode == UInt32(kVK_ANSI_P))
        #expect(hotkey.modifiers == UInt32(cmdKey))

        let spaced = try #require(Hotkey(" Shift + Option + Command + Space "))
        #expect(spaced.keyCode == UInt32(kVK_Space))
        #expect(spaced.modifiers == UInt32(cmdKey | shiftKey | optionKey))
        #expect(spaced.description == "alt+shift+cmd+space")

        #expect(Hotkey("ctrl+⌥+k")?.description == "ctrl+alt+k")
        #expect(Hotkey("f5")?.keyCode == UInt32(kVK_F5))
        #expect(Hotkey("cmd+,")?.keyCode == UInt32(kVK_ANSI_Comma))
    }

    @Test(arguments: ["", "p", "shift+p", "cmd+", "cmd+p+q", "hyper+p", "cmd+nope", "cmd+shift"])
    func rejectsWhatIsntAGlobalShortcut(text: String) {
        #expect(Hotkey(text) == nil)
    }
}
