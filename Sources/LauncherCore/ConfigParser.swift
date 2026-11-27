extension Config {
    /// The settings in `text`, plus a problem for every setting that's wrong or unknown (decision 59). `previous` is
    /// the settings Pith has now, nil at launch. A wrong setting keeps its value there (at launch, `atLaunch`'s), and
    /// the rest still apply; a setting the file doesn't write has its default. A file that isn't valid TOML changes
    /// nothing.
    public static func parse(_ text: String, previous: Config? = nil) -> (config: Config, problems: [String]) {
        let tables: [String: [String: TOMLReader.Entry]]
        do {
            tables = try TOMLReader.parse(text)
        } catch {
            return unchanged(error.description, previous: previous)
        }
        var parser = Parser(fallback: previous ?? atLaunch)
        for (table, entries) in tables {
            for (key, entry) in entries { parser.read(Setting(table: table, key: key, line: entry.line), entry.value) }
        }
        return parser.finish()
    }

    /// One setting as written: `key` in `[table]`, on `line`.
    private struct Setting {
        let table: String
        let key: String
        let line: Int

        /// As problems name it: `launcher.max_depth`.
        var name: String { table.isEmpty ? key : "\(table).\(key)" }
    }

    /// Reads the settings one at a time into a `Config`, with a problem for each one that's wrong or unknown.
    private struct Parser {
        /// What a wrong setting keeps: the settings Pith has now, or at launch `atLaunch`'s.
        let fallback: Config
        var config = Config()
        var problems: [(line: Int, message: String)] = []
        /// `[keys]` as written, resolved together at the end: a key given twice stays with the first setting.
        var writtenKeys: [(key: PanelKey, line: Int, shortcuts: [Shortcut])] = []
        /// The line each hotkey is set on, for the problem when two are the same key.
        var hotkeyLines: [String: Int] = [:]
        /// `[open_with]` as written, settled at the end (`settleOpenWith`): each type and the app it's given, on which
        /// line, and how it's given: 0 on a line of its own, 1 in an app's list, 2 kept from before a wrong value.
        var openWithClaims: [(type: String, app: String, line: Int, form: Int)] = []

        init(fallback: Config) {
            self.fallback = fallback
        }

        mutating func read(_ setting: Setting, _ value: TOMLValue) {
            switch setting.name {
            case "hotkeys.launcher", "hotkeys.clipboard", "hotkeys.paste_next":
                readHotkey(setting, value)
            case "launcher.clipboard_alias", "launcher.empty_state", "launcher.launch_at_login", "launcher.folders",
                "launcher.ignore", "launcher.max_depth":
                readLauncher(setting, value)
            case "clipboard.max_size_gb", "clipboard.max_age_days":
                readClipboard(setting, value)
            case "actions.terminal":
                if case .string(let app) = value {
                    config.terminal = app
                } else {
                    problem("actions.terminal should be a string in quotes", setting)
                }
            default:
                switch setting.table {
                case "keys": readPanelKey(setting, value)
                case "open_with": readOpenWith(setting, value)
                case "open_links": readOpenLinks(setting, value)
                default: problem("unknown setting \"\(setting.name)\"", setting)
                }
            }
        }

        /// A wrong value: the setting stays as it was.
        private mutating func problem(_ message: String, _ setting: Setting) {
            problems.append((setting.line, "line \(setting.line): \(message)"))
            keep(setting)
        }

        private mutating func keep(_ setting: Setting) {
            switch setting.name {
            case "hotkeys.launcher": config.launcherHotkey = fallback.launcherHotkey
            case "hotkeys.clipboard": config.clipboardHotkey = fallback.clipboardHotkey
            case "hotkeys.paste_next": config.pasteNextHotkey = fallback.pasteNextHotkey
            case "launcher.empty_state": config.emptyState = fallback.emptyState
            case "launcher.clipboard_alias": config.clipboardAlias = fallback.clipboardAlias
            case "launcher.launch_at_login": config.launchAtLogin = fallback.launchAtLogin
            case "launcher.folders": config.folders = fallback.folders
            case "launcher.ignore": config.ignore = fallback.ignore
            case "launcher.max_depth": config.maxDepth = fallback.maxDepth
            case "actions.terminal": config.terminal = fallback.terminal
            case "clipboard.max_size_gb": config.clipboardMaxSizeGB = fallback.clipboardMaxSizeGB
            case "clipboard.max_age_days": config.clipboardMaxAgeDays = fallback.clipboardMaxAgeDays
            default:
                let (table, key) = (setting.table, setting.key)
                if table == "keys", let panelKey = PanelKey(rawValue: key) {
                    writtenKeys.append((panelKey, setting.line, fallback.keys[panelKey]))
                } else if table == "open_with" {
                    // Either form, since a wrong value doesn't say which was meant: the type the key names, and the
                    // types the app it names had.
                    if let app = fallback.openWith[fileType(key)] {
                        openWithClaims.append((fileType(key), app, setting.line, 2))
                    }
                    for (type, app) in fallback.openWith where app == key {
                        openWithClaims.append((type, app, setting.line, 2))
                    }
                } else if table == "open_links", let scheme = scheme(key) {
                    config.openLinks[scheme] = fallback.openLinks[scheme]
                }
            }
        }

        /// `[hotkeys]`: a shortcut that works from any app, or "" to turn one off (but not the launcher's).
        private mutating func readHotkey(_ setting: Setting, _ value: TOMLValue) {
            let (name, key) = (setting.name, setting.key)
            guard case .string(let text) = value else {
                return problem("\(name) should be a string in quotes", setting)
            }
            if text.isEmpty {
                guard name != "hotkeys.launcher" else {
                    return problem("hotkeys.launcher can't be off: it's how Pith opens", setting)
                }
                hotkeyLines[key] = setting.line
                if key == "clipboard" { config.clipboardHotkey = nil } else { config.pasteNextHotkey = nil }
                return
            }
            let hotkey = Shortcut(text)
            if let hotkey, let editing = KeyBindings.editingKeys.first(where: { $0.shortcut == hotkey }) {
                // A hotkey takes its key from every app: ⌘V would paste nowhere, Pith's own paste included.
                problem("\(name) \"\(text)\" is \(editing.name) in every app, so it's left as it was", setting)
            } else if let hotkey, hotkey.isGlobal {
                hotkeyLines[key] = setting.line
                switch key {
                case "launcher": config.launcherHotkey = hotkey
                case "clipboard": config.clipboardHotkey = hotkey
                default: config.pasteNextHotkey = hotkey
                }
            } else {
                problem("\(name) \"\(text)\" isn't a shortcut like \"cmd+p\"", setting)
            }
        }

        /// `[keys]`: one key, a list of them, or "" or [] for none.
        private mutating func readPanelKey(_ setting: Setting, _ value: TOMLValue) {
            let name = setting.name
            guard let panelKey = PanelKey(rawValue: setting.key) else {
                return problem("unknown setting \"\(name)\"", setting)
            }
            let values: [TOMLValue] =
                switch value {
                case .string(""): []
                case .array(let values): values
                default: [value]
                }
            let texts = values.compactMap { if case .string(let text) = $0 { text } else { nil } }
            guard texts.count == values.count else {
                return problem(
                    "\(name) should be a key in quotes, or a list of them like [\"up\", \"ctrl+k\"]", setting)
            }
            if let bad = texts.first(where: { Shortcut($0) == nil }) {
                problem("\(name) \"\(bad)\" isn't a key like \"ctrl+k\" or \"up\"", setting)
            } else {
                writtenKeys.append((panelKey, setting.line, texts.compactMap(Shortcut.init)))
            }
        }

        private mutating func readLauncher(_ setting: Setting, _ value: TOMLValue) {
            let name = setting.name
            switch (name, value) {
            case ("launcher.clipboard_alias", .string(let text)):
                let alias = text.lowercased()
                if alias.contains(where: \.isWhitespace) {
                    problem("launcher.clipboard_alias \"\(text)\" should be one word, like \"c\"", setting)
                } else {
                    config.clipboardAlias = alias
                }
            case ("launcher.empty_state", .string(let text)):
                if let emptyState = EmptyState(rawValue: text) {
                    config.emptyState = emptyState
                } else {
                    problem(
                        "launcher.empty_state is \"\(text)\", expected \"recent\", \"running\" or \"none\"", setting)
                }
            case ("launcher.launch_at_login", .boolean(let on)):
                config.launchAtLogin = on
            case ("launcher.folders", .array(let values)), ("launcher.ignore", .array(let values)):
                let strings = values.compactMap { if case .string(let text) = $0 { text } else { nil } }
                guard strings.count == values.count else {
                    return problem("\(name) should be a list of strings, like [\"~/Documents\"]", setting)
                }
                if setting.key == "folders" { config.folders = strings } else { config.ignore = strings }
            case ("launcher.max_depth", .integer(let depth)):
                if (1...32).contains(depth) {
                    config.maxDepth = depth
                } else {
                    problem("launcher.max_depth is \(depth), expected 1 to 32", setting)
                }
            case ("launcher.empty_state", _), ("launcher.clipboard_alias", _):
                problem("\(name) should be a string in quotes", setting)
            case ("launcher.launch_at_login", _):
                problem("launcher.launch_at_login should be true or false", setting)
            case ("launcher.folders", _), ("launcher.ignore", _):
                problem("\(name) should be a list of strings, like [\"~/Documents\"]", setting)
            default:
                problem("launcher.max_depth should be a number", setting)
            }
        }

        private mutating func readClipboard(_ setting: Setting, _ value: TOMLValue) {
            switch (setting.name, value) {
            case ("clipboard.max_size_gb", .integer(let gigabytes)):
                readSize(Double(gigabytes), as: "\(gigabytes)", setting)
            case ("clipboard.max_size_gb", .float(let gigabytes)):
                readSize(gigabytes, as: "\(gigabytes)", setting)
            case ("clipboard.max_age_days", .integer(let days)):
                if (1...3_650).contains(days) {
                    config.clipboardMaxAgeDays = days
                } else {
                    problem("clipboard.max_age_days is \(days), expected 1 to 3650", setting)
                }
            case ("clipboard.max_size_gb", _):
                problem("clipboard.max_size_gb should be a number, like 2 or 0.5", setting)
            default:
                problem("clipboard.max_age_days should be a whole number of days", setting)
            }
        }

        private mutating func readSize(_ gigabytes: Double, as written: String, _ setting: Setting) {
            if gigabytes > 0, gigabytes <= 1_000 {
                config.clipboardMaxSizeGB = gigabytes
            } else {
                problem("clipboard.max_size_gb is \(written), expected more than 0 and at most 1000", setting)
            }
        }

        /// `[open_with]`: a type and its app, `md = "Preview"`, or an app and its types, `"Preview" = ["md", "txt"]`
        /// (decision 82).
        private mutating func readOpenWith(_ setting: Setting, _ value: TOMLValue) {
            switch value {
            case .string(let app):
                openWithClaims.append((fileType(setting.key), app, setting.line, 0))
            case .array(let items):
                let types = items.compactMap { item -> String? in if case .string(let type) = item { type } else { nil }
                }
                guard types.count == items.count else {
                    return problem(
                        "open_with.\"\(setting.key)\" should list extensions in quotes, like [\"md\", \"txt\"]", setting
                    )
                }
                for type in types { openWithClaims.append((fileType(type), setting.key, setting.line, 1)) }
            default:
                problem("open_with.\(setting.key) should be an app name in quotes, or a list of extensions", setting)
            }
        }

        /// Gives each `[open_with]` type one app: a line of its own before an app's list, then the earlier line. A
        /// type given two apps is a problem on the line that loses; one kept from before a wrong value gives way
        /// quietly, as does the same app given twice.
        private mutating func settleOpenWith() {
            var settled: [String: (app: String, line: Int)] = [:]
            for claim in openWithClaims.sorted(by: { ($0.form, $0.line) < ($1.form, $1.line) }) {
                guard let winner = settled[claim.type] else {
                    settled[claim.type] = (claim.app, claim.line)
                    continue
                }
                if claim.form < 2, claim.line != winner.line,
                    claim.app.caseInsensitiveCompare(winner.app) != .orderedSame
                {
                    problems.append(
                        (
                            claim.line,
                            "line \(claim.line): open_with sets \"\(claim.type)\" on line \(winner.line) too, so it opens in \"\(winner.app)\""
                        ))
                }
            }
            config.openWith = settled.mapValues(\.app)
        }

        private mutating func readOpenLinks(_ setting: Setting, _ value: TOMLValue) {
            guard case .string(let app) = value else {
                return problem("open_links.\(setting.key) should be an app name in quotes", setting)
            }
            if let scheme = scheme(setting.key) {
                config.openLinks[scheme] = app
            } else {
                problem("open_links \"\(setting.key)\" isn't a URL scheme like \"https\"", setting)
            }
        }

        /// The config and its problems, in file order, once every setting is read: the hotkeys kept apart, and the
        /// panel's keys resolved around them.
        mutating func finish() -> (config: Config, problems: [String]) {
            settleOpenWith()
            let hotkeys = separateHotkeys()
            let keys = KeyBindings.resolve(written: writtenKeys, hotkeys: hotkeys)
            config.keys = keys.bindings
            problems += keys.problems
            return (config, problems.sorted { $0.line < $1.line }.map(\.message))
        }

        /// One key can't be two hotkeys: the first of launcher, clipboard and paste_next keeps it, and the problem is
        /// on the later line of the two. Returns the hotkeys that are on.
        private mutating func separateHotkeys() -> [(name: String, shortcut: Shortcut)] {
            var hotkeys = [(name: "launcher", shortcut: config.launcherHotkey)]
            for (name, setting) in [("clipboard", \Config.clipboardHotkey), ("paste_next", \Config.pasteNextHotkey)] {
                guard let hotkey = config[keyPath: setting] else { continue }
                guard let owner = hotkeys.first(where: { $0.shortcut == hotkey }) else {
                    hotkeys.append((name, hotkey))
                    continue
                }
                config[keyPath: setting] = nil
                let line = max(hotkeyLines[owner.name] ?? 0, hotkeyLines[name] ?? 0)
                problems.append(
                    (
                        line,
                        "line \(line): hotkeys.\(owner.name) and hotkeys.\(name) are both \"\(hotkey)\", so hotkeys.\(name) is off"
                    ))
            }
            return hotkeys
        }

        /// An `[open_with]` type as it's looked up: lowercased, without a leading `*.` or `.`, so "*.MD" is "md".
        private func fileType(_ key: String) -> String {
            key.lowercased().trimmingPrefix("*").trimmingPrefix(".").description
        }

        /// An `[open_links]` key as a lowercased URL scheme ("https:" and "https://" mean "https" too), or nil when it
        /// isn't one.
        private func scheme(_ key: String) -> String? {
            var scheme = key.lowercased()
            while scheme.hasSuffix(":") || scheme.hasSuffix("/") { scheme.removeLast() }
            guard let first = scheme.first, first.isASCII, first.isLetter,
                scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) })
            else { return nil }
            return scheme
        }
    }
}
