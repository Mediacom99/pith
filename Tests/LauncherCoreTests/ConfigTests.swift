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
        #expect(config.clipboardHotkey?.description == "shift+cmd+v", "the modifiers in macOS order")
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

    @Test func readsTheClipboardsLimitsAndTheLinksApps() {
        #expect(Config().clipboardRetention == .init(maxBytes: 2_000_000_000, maxAge: 30 * 86_400), "decision 37")
        let (config, problems) = Config.parse(
            """
            [clipboard]
            max_size_gb = 0.5
            max_age_days = 7
            [open_links]
            HTTPS = "Firefox"
            "mailto:" = "Mail"
            "x-man-page" = "Terminal"
            """)
        #expect(problems.isEmpty)
        #expect(config.clipboardRetention == .init(maxBytes: 500_000_000, maxAge: 7 * 86_400))
        #expect(config.openLinks == ["https": "Firefox", "mailto": "Mail", "x-man-page": "Terminal"])
        #expect(Config.parse("clipboard.max_size_gb = 3").config.clipboardMaxSizeGB == 3, "a whole number too")
    }

    @Test func badClipboardAndLinkSettingsAreReported() {
        let (config, problems) = Config.parse(
            """
            [clipboard]
            max_size_gb = 0
            max_age_days = 1.5
            [open_links]
            "https://acme.example" = "Safari"
            mailto = 3
            """)
        var expected = Config()
        expected.clipboardMaxSizeGB = nil
        expected.clipboardMaxAgeDays = nil
        #expect(config == expected, "at launch, a wrong limit drops nothing (decision 59)")
        #expect(config.clipboardRetention == .init(maxBytes: .max, maxAge: .infinity))
        #expect(
            problems == [
                "line 2: clipboard.max_size_gb is 0, expected more than 0 and at most 1000",
                "line 3: clipboard.max_age_days should be a whole number of days",
                "line 5: open_links \"https://acme.example\" isn't a URL scheme like \"https\"",
                "line 6: open_links.mailto should be an app name in quotes",
            ])
        #expect(
            Config.parse("[clipboard]\nmax_size_gb = \"2\"\nmax_age_days = 0").problems == [
                "line 2: clipboard.max_size_gb should be a number, like 2 or 0.5",
                "line 3: clipboard.max_age_days is 0, expected 1 to 3650",
            ])
    }

    @Test func invalidTOMLChangesNothing() {
        let broken = "[launcher]\nempty_state = \"recent\nlaunch_at_login = true"
        var current = Config()
        current.emptyState = .none
        current.clipboardMaxAgeDays = 365
        let (config, problems) = Config.parse(broken, previous: current)
        #expect(config == current, "decision 59")
        #expect(problems == ["line 2: unterminated string, so the settings stay as they were"])

        #expect(
            Config.parse("terminal = “Ghostty”").problems == [
                "line 1: curly quotes, expected straight ones (\"), so every setting is at its default and no clipboard history is dropped"
            ])

        let (atLaunch, launchProblems) = Config.parse(broken)
        #expect(atLaunch.emptyState == .recent)
        #expect(atLaunch.clipboardRetention == .init(maxBytes: .max, maxAge: .infinity), "no clipboard history dropped")
        #expect(
            launchProblems == [
                "line 2: unterminated string, so every setting is at its default and no clipboard history is dropped"
            ])
    }

    /// A wrong value keeps what Pith has now; what's right applies, and what isn't written goes back to its default.
    @Test func aWrongSettingStaysAsItWas() {
        var current = Config()
        current.clipboardMaxAgeDays = 365
        current.clipboardMaxSizeGB = 10
        current.launchAtLogin = false
        current.clipboardHotkey = nil
        current.terminal = "Ghostty"
        current.folders = ["~/dev"]
        current.openWith = ["md": "Visual Studio Code"]
        current.keys = Config.parse("[keys]\nup = \"ctrl+p\"").config.keys
        let (config, problems) = Config.parse(
            """
            [hotkeys]
            clipboard = "cmd+"
            [keys]
            up = "ctrl+"
            [launcher]
            empty_state = "none"
            launch_at_login = "no"
            [clipboard]
            max_age_days = 9999
            max_size_gb = 4
            [actions]
            terminal = 3
            [open_with]
            md = 1
            """, previous: current)
        #expect(problems.count == 6)
        #expect(config.clipboardMaxAgeDays == 365, "a mistake never deletes history")
        #expect(config.clipboardMaxSizeGB == 4)
        #expect(config.launchAtLogin == false)
        #expect(config.clipboardHotkey == nil)
        #expect(config.keys[.up] == [Shortcut("ctrl+p")!])
        #expect(config.terminal == "Ghostty")
        #expect(config.openWith == ["md": "Visual Studio Code"])
        #expect(config.emptyState == .none)
        #expect(config.folders == Config().folders, "not written: the default")
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

struct ShortcutTests {
    @Test func readsShortcuts() throws {
        let hotkey = try #require(Shortcut("cmd+p"))
        #expect(hotkey.keyCode == UInt32(kVK_ANSI_P))
        #expect(hotkey.modifiers == UInt32(cmdKey))

        let spaced = try #require(Shortcut(" Shift + Option + Command + Space "))
        #expect(spaced.keyCode == UInt32(kVK_Space))
        #expect(spaced.modifiers == UInt32(cmdKey | shiftKey | optionKey))
        #expect(spaced.description == "alt+shift+cmd+space")

        #expect(Shortcut("ctrl+⌥+k")?.description == "ctrl+alt+k")
        #expect(Shortcut("f5")?.keyCode == UInt32(kVK_F5))
        #expect(Shortcut("cmd+,")?.keyCode == UInt32(kVK_ANSI_Comma))
        #expect(Shortcut("delete") == Shortcut("backspace"))
        #expect(Shortcut("enter")?.description == "return")
    }

    @Test(arguments: ["", "cmd+", "cmd+p+q", "hyper+p", "cmd+nope", "cmd+shift"])
    func rejectsWhatIsntAKey(text: String) {
        #expect(Shortcut(text) == nil)
    }

    @Test func onlyAModifierOrAFunctionKeyMakesAGlobalHotkey() throws {
        #expect(try #require(Shortcut("cmd+p")).isGlobal)
        #expect(try #require(Shortcut("f13")).isGlobal)
        #expect(try !#require(Shortcut("p")).isGlobal)
        #expect(try !#require(Shortcut("shift+p")).isGlobal)
        #expect(try !#require(Shortcut("up")).isGlobal)
    }

    @Test func keysThatTypeAreCharactersSpaceAndBackspace() throws {
        for text in ["k", "shift+k", "space", "backspace", "/"] { #expect(try #require(Shortcut(text)).typesText) }
        for text in ["up", "return", "escape", "ctrl+k", "cmd+y", "alt+k"] {
            #expect(try !#require(Shortcut(text)).typesText)
        }
    }

    @Test func readAsMenusAndKeyCapsShowThem() throws {
        #expect(try #require(Shortcut("cmd+shift+v")).symbols == "⇧⌘V")
        #expect(try #require(Shortcut("cmd+p")).symbols == "⌘P")
        #expect(try #require(Shortcut("ctrl+alt+space")).symbols == "⌃⌥Space")
        #expect(try #require(Shortcut("cmd+return")).symbols == "⌘↩")
        #expect(try #require(Shortcut("cmd+k")).caps == ["⌘", "K"])
        #expect(try #require(Shortcut("escape")).caps == ["esc"])
        #expect(try #require(Shortcut("return")).caps == ["↩"])
        #expect(try #require(Shortcut("ctrl+j")).caps == ["⌃", "J"])
    }

    @Test func charactersMatchByWhatTheyTypeOtherKeysByPosition() throws {
        let k = try #require(Shortcut("cmd+k"))
        let cmd = UInt32(cmdKey)
        #expect(k.matches(keyCode: UInt32(kVK_ANSI_K), modifiers: cmd, character: "k"))
        #expect(
            k.matches(keyCode: UInt32(kVK_ANSI_T), modifiers: cmd, character: "k"),
            "a layout with k elsewhere: the key that types k")
        #expect(!k.matches(keyCode: UInt32(kVK_ANSI_K), modifiers: cmd, character: "t"))
        #expect(!k.matches(keyCode: UInt32(kVK_ANSI_K), modifiers: cmd | UInt32(shiftKey), character: "k"))
        let up = try #require(Shortcut("up"))
        #expect(up.matches(keyCode: UInt32(kVK_UpArrow), modifiers: 0, character: "\u{F700}"))
        #expect(!up.matches(keyCode: UInt32(kVK_DownArrow), modifiers: 0, character: nil))
    }
}

struct KeysConfigTests {
    private func keys(_ text: String) -> (keys: KeyBindings, problems: [String]) {
        let (config, problems) = Config.parse(text)
        return (config.keys, problems)
    }

    @Test func defaultsAreTheKeysTheyReplace() {
        let keys = Config().keys
        #expect(keys[.up].map(\.description) == ["up", "ctrl+k"])
        #expect(keys[.down].map(\.description) == ["down", "ctrl+j"])
        #expect(keys[.open].map(\.description) == ["return"])
        #expect(keys[.actions].map(\.description) == ["cmd+k"])
        #expect(keys[.back].map(\.description) == ["escape"])
        #expect(keys[.preview].map(\.description) == ["cmd+y", "space"], "⌘Y and Space (decision 20)")
        #expect(keys.runActions.map { $0?.symbols } == ["⌘Q", "⌘W", "⌘E", "⌘R", "⌘T", "⌘Y", "⌘U"], "decision 43")
        #expect(keys[.toLauncher].map(\.description) == ["backspace"])
        #expect(Config().clipboardAlias == "c")
    }

    @Test func readsOneKeyOrAList() {
        let (keys, problems) = keys(
            """
            [keys]
            up = "ctrl+p"
            down = ["ctrl+n", "down"]
            actions = "cmd+."
            run_actions = ["ctrl+1", "ctrl+2"]
            """)
        #expect(problems.isEmpty)
        #expect(keys[.up].map(\.description) == ["ctrl+p"])
        #expect(keys[.down].map(\.description) == ["ctrl+n", "down"])
        #expect(keys[.actions].map(\.description) == ["cmd+."])
        #expect(keys.runActions.map { $0?.description } == ["ctrl+1", "ctrl+2"])
        #expect(keys[.open].map(\.description) == ["return"], "the others keep their defaults")
    }

    @Test func emptyTurnsAKeyOffButNotOpenOrBack() {
        let (keys, problems) = keys(
            """
            [keys]
            preview = []
            to_launcher = ""
            open = []
            back = ""
            """)
        #expect(keys[.preview].isEmpty)
        #expect(keys[.toLauncher].isEmpty)
        #expect(keys[.open].map(\.description) == ["return"])
        #expect(keys[.back].map(\.description) == ["escape"])
        #expect(
            problems == [
                "line 4: keys.open needs a key, so it's \"return\"",
                "line 5: keys.back needs a key, so it's \"escape\"",
            ])
    }

    @Test func aBadValueKeepsTheDefault() {
        let (keys, problems) = keys(
            """
            [keys]
            up = ["up", "ctrl+"]
            down = 3
            back = [1]
            sideways = "left"
            """)
        #expect(keys == Config().keys)
        #expect(
            problems == [
                "line 2: keys.up \"ctrl+\" isn't a key like \"ctrl+k\" or \"up\"",
                "line 3: keys.down should be a key in quotes, or a list of them like [\"up\", \"ctrl+k\"]",
                "line 4: keys.back should be a key in quotes, or a list of them like [\"up\", \"ctrl+k\"]",
                "line 5: unknown setting \"keys.sideways\"",
            ])
    }

    @Test func aKeyGivenTwiceStaysWithTheFirst() {
        let (keys, problems) = keys(
            """
            [keys]
            up = ["up", "ctrl+k"]
            down = ["down", "ctrl+k"]
            open = ["return", "cmd+c"]
            actions = ["cmd+k", "cmd+p"]
            preview = ["cmd+y", "cmd+y"]
            """)
        #expect(keys[.down].map(\.description) == ["down"])
        #expect(keys[.open].map(\.description) == ["return"])
        #expect(keys[.actions].map(\.description) == ["cmd+k"])
        #expect(keys[.preview].map(\.description) == ["cmd+y"])
        #expect(
            problems == [
                "line 3: keys.down \"ctrl+k\" is already keys.up, so it's left out",
                "line 4: keys.open \"cmd+c\" is Copy in the search field, so it's left out",
                "line 5: keys.actions \"cmd+p\" is hotkeys.launcher, so it's left out",
                "line 6: keys.preview \"cmd+y\" is there twice, so it's left out",
            ])
    }

    @Test func aWrittenKeyQuietlyTakesItFromADefault() {
        let (keys, problems) = keys("[keys]\nup = [\"ctrl+j\"]")
        #expect(problems.isEmpty)
        #expect(keys[.up].map(\.description) == ["ctrl+j"])
        #expect(keys[.down].map(\.description) == ["down"])
    }

    @Test func anActionLeftOutKeepsTheOthersInPlace() {
        let (keys, problems) = keys("[keys]\nactions = \"cmd+k\"\nrun_actions = [\"cmd+q\", \"cmd+k\", \"cmd+e\"]")
        #expect(keys.runActions.map { $0?.description } == ["cmd+q", nil, "cmd+e"], "⌘E is still the third")
        #expect(problems == ["line 3: keys.run_actions \"cmd+k\" is already keys.actions, so it's left out"])
    }

    @Test func actionsMayShareWithQuickLookAndTheWayBack() {
        let (keys, problems) = keys(
            """
            [keys]
            run_actions = ["cmd+y", "backspace"]
            """)
        #expect(problems.isEmpty, "inside an actions list, run_actions comes first")
        #expect(keys.runActions.map { $0?.description } == ["cmd+y", "backspace"])
        #expect(keys[.preview].map(\.description) == ["cmd+y", "space"])
    }

    @Test func aHotkeyCanBeTurnedOffButNotTheLaunchers() {
        let (config, problems) = Config.parse(
            """
            [hotkeys]
            launcher = ""
            clipboard = ""
            """)
        #expect(config.clipboardHotkey == nil, "⌘⇧V goes back to the apps")
        #expect(config.launcherHotkey.description == "cmd+p")
        #expect(problems == ["line 2: hotkeys.launcher can't be off: it's how Pith opens"])
    }

    @Test func oneHotkeyCantOpenBoth() {
        let (config, problems) = Config.parse("[hotkeys]\nlauncher = \"cmd+shift+v\"")
        #expect(config.launcherHotkey.description == "shift+cmd+v")
        #expect(config.clipboardHotkey == nil)
        #expect(
            problems == [
                "line 2: hotkeys.launcher and hotkeys.clipboard are both \"shift+cmd+v\", so the clipboard's is off"
            ])
    }

    @Test func readsTheClipboardAlias() {
        #expect(Config.parse("launcher.clipboard_alias = \"V\"").config.clipboardAlias == "v")
        #expect(Config.parse("launcher.clipboard_alias = \"\"").config.clipboardAlias == "")
        let (config, problems) = Config.parse("launcher.clipboard_alias = \"c b\"")
        #expect(config.clipboardAlias == "c")
        #expect(problems == ["line 1: launcher.clipboard_alias \"c b\" should be one word, like \"c\""])
    }
}
