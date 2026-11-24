import Foundation

/// The settings in `~/.config/pith/config.toml`. Every one has a default, so a missing file or key is fine.
public struct Config: Sendable, Equatable {
    /// What the launcher lists before you type (decisions 11–13).
    public enum EmptyState: String, Sendable, CaseIterable {
        /// What you opened last, newest first.
        case recent
        /// Open apps, most recently used first.
        case running
        /// Just the search bar.
        case none
    }

    public var launcherHotkey = Shortcut("cmd+p")!
    /// Opens the panel straight in the clipboard (decision 34). Nil when it's off, which leaves the key to apps.
    public var clipboardHotkey = Shortcut("cmd+shift+v")
    /// Pastes the clip copied right after the one pasted last (decision 63). Nil when it's off.
    public var pasteNextHotkey = Shortcut("ctrl+alt+v")
    /// The keys inside the panel (decision 55).
    public var keys = KeyBindings.defaults
    /// Clipboard History's alias in the launcher (decision 42); followed by a space, it opens the clipboard. Empty
    /// for neither.
    public var clipboardAlias = "c"
    public var emptyState = EmptyState.recent
    /// Applies to the copy installed in an Applications folder (decision 14).
    public var launchAtLogin = true
    /// Folders whose files and folders are searched (decision 22). `~` is the home folder.
    public var folders = ["~"]
    /// Names, globs and paths to skip (see `IgnoreRules`).
    public var ignore = [".*", "~/Library", "node_modules", ".build", "*.photoslibrary"]
    /// How many folders deep the file index goes.
    public var maxDepth = 6
    /// The app "Open in terminal" uses: a name, bundle id or path.
    public var terminal = "Terminal"
    /// Which app opens files of a type when opened from the launcher (decision 15): a lowercased extension (`md`) or
    /// a type identifier (`public.image`) → an app name, bundle id or path.
    public var openWith: [String: String] = [:]
    /// Which app opens links of a URL scheme (decision 16): a lowercased scheme (`https`, `mailto`) → an app name,
    /// bundle id or path.
    public var openLinks: [String: String] = [:]
    /// How much clipboard history is kept (decision 37): whichever limit is reached first drops the oldest unpinned
    /// clips. Nil when the file's value is wrong and Pith has none from before to keep, at launch: that limit then
    /// drops nothing, so a mistake never deletes history (decision 59).
    public var clipboardMaxSizeGB: Double? = 2
    public var clipboardMaxAgeDays: Int? = 30

    public init() {}

    /// The clipboard's limits, as the store applies them. A limit that's nil drops nothing.
    public var clipboardRetention: ClipboardStore.Retention {
        ClipboardStore.Retention(
            maxBytes: clipboardMaxSizeGB.map { Int($0 * 1_000_000_000) } ?? .max,
            maxAge: clipboardMaxAgeDays.map { TimeInterval($0) * 86_400 } ?? .infinity)
    }

    /// The folders in the home folder that macOS asks about before an app reads them (decision 60).
    static let protectedFolders = ["Desktop", "Documents", "Downloads", "Library/Mobile Documents/com~apple~CloudDocs"]

    /// What a wrong setting falls back to at launch, when Pith has no settings yet: its default, except the
    /// clipboard's limits, which drop nothing until the file sets them right (decision 59).
    static var atLaunch: Config {
        var config = Config()
        config.clipboardMaxSizeGB = nil
        config.clipboardMaxAgeDays = nil
        return config
    }

    /// The settings when config.toml can't be read or isn't valid TOML: `previous`, the ones Pith has now, unchanged,
    /// or at launch `atLaunch`, with one problem that says why (decision 59).
    public static func unchanged(_ reason: String, previous: Config?) -> (config: Config, problems: [String]) {
        if let previous { return (previous, ["\(reason), so the settings stay as they were"]) }
        return (atLaunch, ["\(reason), so every setting is at its default and no clipboard history is dropped"])
    }

    /// What the file index scans, with `~` expanded and symlinks resolved: FSEvents reports real paths, so a
    /// symlinked folder would otherwise never see its changes.
    public func fileRules(home: String = NSHomeDirectory()) -> FileRules {
        let roots = folders.map { folder -> String in
            var path = folder == "~" || folder.hasPrefix("~/") ? home + folder.dropFirst() : folder
            if let real = realpath(path, nil) {
                path = String(cString: real)
                free(real)
            }
            while path.count > 1, path.hasSuffix("/") { path.removeLast() }
            return path
        }
        return FileRules(
            roots: roots, ignore: IgnoreRules(ignore, home: home), maxDepth: maxDepth,
            protected: Self.protectedFolders.map { home + "/" + $0 })
    }

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

        var config = Config()
        let fallback = previous ?? atLaunch
        var problems: [(line: Int, message: String)] = []
        var writtenKeys: [(key: PanelKey, line: Int, shortcuts: [Shortcut])] = []
        var hotkeyLines: [String: Int] = [:]
        for (table, entries) in tables {
            for (key, entry) in entries {
                let name = table.isEmpty ? key : "\(table).\(key)"
                /// A wrong value: the setting stays as it was.
                func keep() {
                    switch name {
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
                        if table == "keys", let panelKey = PanelKey(rawValue: key) {
                            writtenKeys.append((panelKey, entry.line, fallback.keys[panelKey]))
                        } else if table == "open_with" {
                            config.openWith[fileType(key)] = fallback.openWith[fileType(key)]
                        } else if table == "open_links", let scheme = scheme(key) {
                            config.openLinks[scheme] = fallback.openLinks[scheme]
                        }
                    }
                }
                func problem(_ message: String) {
                    problems.append((entry.line, "line \(entry.line): \(message)"))
                    keep()
                }
                func size(_ gigabytes: Double, as written: String) {
                    if gigabytes > 0, gigabytes <= 1_000 {
                        config.clipboardMaxSizeGB = gigabytes
                    } else {
                        problem("clipboard.max_size_gb is \(written), expected more than 0 and at most 1000")
                    }
                }
                switch (name, entry.value) {
                case ("hotkeys.launcher", .string("")):
                    problem("hotkeys.launcher can't be off: it's how Pith opens")
                case ("hotkeys.clipboard", .string("")), ("hotkeys.paste_next", .string("")):
                    hotkeyLines[key] = entry.line
                    if key == "clipboard" { config.clipboardHotkey = nil } else { config.pasteNextHotkey = nil }
                case ("hotkeys.launcher", .string(let text)), ("hotkeys.clipboard", .string(let text)),
                    ("hotkeys.paste_next", .string(let text)):
                    if let hotkey = Shortcut(text),
                        let editing = KeyBindings.editingKeys.first(where: {
                            $0.shortcut == hotkey
                        })
                    {
                        // A hotkey takes its key from every app: ⌘V would paste nowhere, Pith's own paste included.
                        problem("\(name) \"\(text)\" is \(editing.name) in every app, so it's left as it was")
                    } else if let hotkey = Shortcut(text), hotkey.isGlobal {
                        hotkeyLines[key] = entry.line
                        switch key {
                        case "launcher": config.launcherHotkey = hotkey
                        case "clipboard": config.clipboardHotkey = hotkey
                        default: config.pasteNextHotkey = hotkey
                        }
                    } else {
                        problem("\(name) \"\(text)\" isn't a shortcut like \"cmd+p\"")
                    }
                case (_, let value) where table == "keys":
                    guard let panelKey = PanelKey(rawValue: key) else {
                        problem("unknown setting \"\(name)\"")
                        break
                    }
                    // One key, a list of them, or "" or [] for none.
                    let values: [TOMLValue] =
                        switch value {
                        case .string(""): []
                        case .array(let values): values
                        default: [value]
                        }
                    let texts = values.compactMap { if case .string(let text) = $0 { text } else { nil } }
                    guard texts.count == values.count else {
                        problem("\(name) should be a key in quotes, or a list of them like [\"up\", \"ctrl+k\"]")
                        break
                    }
                    let shortcuts = texts.compactMap(Shortcut.init)
                    if let bad = texts.first(where: { Shortcut($0) == nil }) {
                        problem("\(name) \"\(bad)\" isn't a key like \"ctrl+k\" or \"up\"")
                    } else {
                        writtenKeys.append((panelKey, entry.line, shortcuts))
                    }
                case ("launcher.clipboard_alias", .string(let text)):
                    let alias = text.lowercased()
                    if alias.contains(where: \.isWhitespace) {
                        problem("launcher.clipboard_alias \"\(text)\" should be one word, like \"c\"")
                    } else {
                        config.clipboardAlias = alias
                    }
                case ("launcher.empty_state", .string(let text)):
                    if let emptyState = EmptyState(rawValue: text) {
                        config.emptyState = emptyState
                    } else {
                        problem("launcher.empty_state is \"\(text)\", expected \"recent\", \"running\" or \"none\"")
                    }
                case ("launcher.launch_at_login", .boolean(let on)):
                    config.launchAtLogin = on
                case ("launcher.folders", .array(let values)), ("launcher.ignore", .array(let values)):
                    let strings = values.compactMap { if case .string(let text) = $0 { text } else { nil } }
                    guard strings.count == values.count else {
                        problem("\(name) should be a list of strings, like [\"~/Documents\"]")
                        break
                    }
                    if key == "folders" { config.folders = strings } else { config.ignore = strings }
                case ("launcher.max_depth", .integer(let depth)):
                    if (1...32).contains(depth) {
                        config.maxDepth = depth
                    } else {
                        problem("launcher.max_depth is \(depth), expected 1 to 32")
                    }
                case ("actions.terminal", .string(let app)):
                    config.terminal = app
                case (_, .string(let app)) where table == "open_with":
                    config.openWith[fileType(key)] = app
                case (_, _) where table == "open_with":
                    problem("open_with.\(key) should be an app name in quotes")
                case (_, .string(let app)) where table == "open_links":
                    if let scheme = scheme(key) {
                        config.openLinks[scheme] = app
                    } else {
                        problem("open_links \"\(key)\" isn't a URL scheme like \"https\"")
                    }
                case (_, _) where table == "open_links":
                    problem("open_links.\(key) should be an app name in quotes")
                case ("clipboard.max_size_gb", .integer(let gigabytes)):
                    size(Double(gigabytes), as: "\(gigabytes)")
                case ("clipboard.max_size_gb", .float(let gigabytes)):
                    size(gigabytes, as: "\(gigabytes)")
                case ("clipboard.max_age_days", .integer(let days)):
                    if (1...3_650).contains(days) {
                        config.clipboardMaxAgeDays = days
                    } else {
                        problem("clipboard.max_age_days is \(days), expected 1 to 3650")
                    }
                case ("clipboard.max_size_gb", _):
                    problem("clipboard.max_size_gb should be a number, like 2 or 0.5")
                case ("clipboard.max_age_days", _):
                    problem("clipboard.max_age_days should be a whole number of days")
                case ("hotkeys.launcher", _), ("hotkeys.clipboard", _), ("hotkeys.paste_next", _),
                    ("launcher.empty_state", _), ("launcher.clipboard_alias", _), ("actions.terminal", _):
                    problem("\(name) should be a string in quotes")
                case ("launcher.launch_at_login", _):
                    problem("launcher.launch_at_login should be true or false")
                case ("launcher.folders", _), ("launcher.ignore", _):
                    problem("\(name) should be a list of strings, like [\"~/Documents\"]")
                case ("launcher.max_depth", _):
                    problem("launcher.max_depth should be a number")
                default:
                    problem("unknown setting \"\(name)\"")
                }
            }
        }
        // One key can't be two hotkeys: the first of launcher, clipboard and paste_next keeps it, and the problem is
        // on the later line of the two.
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
        let keys = KeyBindings.resolve(written: writtenKeys, hotkeys: hotkeys)
        config.keys = keys.bindings
        problems += keys.problems
        return (config, problems.sorted { $0.line < $1.line }.map(\.message))
    }

    /// An `[open_with]` key as it's looked up: lowercased, without a leading dot.
    private static func fileType(_ key: String) -> String {
        key.lowercased().trimmingPrefix(".").description
    }

    /// An `[open_links]` key as a lowercased URL scheme ("https:" and "https://" mean "https" too), or nil when it
    /// isn't one.
    private static func scheme(_ key: String) -> String? {
        var scheme = key.lowercased()
        while scheme.hasSuffix(":") || scheme.hasSuffix("/") { scheme.removeLast() }
        guard let first = scheme.first, first.isASCII, first.isLetter,
            scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) })
        else { return nil }
        return scheme
    }

    /// Written to a new config file: every setting with its default, explained.
    public static let template = """
        # Pith settings. Saved changes apply right away.

        [hotkeys]
        # Opens the launcher from anywhere: modifiers (cmd, shift, alt, ctrl) + one key.
        launcher = "cmd+p"
        # Opens the clipboard history. It takes the key from every app: cmd+shift+v is Paste and Match Style in many,
        # and the clipboard's Paste as Plain Text does the same. "" turns it off.
        clipboard = "cmd+shift+v"
        # After you paste a clip from the clipboard, pastes the one you copied right after it, then the next, up to
        # the newest: for filling in a form with what you copied in order. A clip pasted as plain text keeps the rest
        # plain. With nothing left to paste, opens the clipboard. "" turns it off.
        paste_next = "ctrl+alt+v"

        [keys]
        # The keys inside Pith: one key, or a list of them like ["up", "ctrl+k"]. [] turns one off.
        # A key is a to z, 0 to 9, punctuation, space, return, tab, escape, backspace, up, down, left, right or f1 to
        # f20, after any modifiers. One without cmd, alt or ctrl (a letter, space, backspace) works only while the
        # search field is empty. A key given twice stays with the first setting.
        up = ["up", "ctrl+k"]
        down = ["down", "ctrl+j"]
        # Opens the selected item, runs the selected action, pastes the selected clip.
        open = "return"
        # The selected item's actions, or back to the search.
        actions = "cmd+k"
        # Back one level, or close.
        back = "escape"
        # Quick Look the selected file.
        preview = ["cmd+y", "space"]
        # In an actions list: run its 1st, 2nd, 3rd… action.
        run_actions = ["cmd+q", "cmd+w", "cmd+e", "cmd+r", "cmd+t", "cmd+y", "cmd+u"]
        # In the clipboard: back to the launcher.
        to_launcher = "backspace"

        [launcher]
        # What the launcher shows before you type:
        #   "recent"   what you opened last, newest first
        #   "running"  open apps, most recently used first
        #   "none"     just the search bar
        empty_state = "recent"

        # Typed alone, lists Clipboard History first; with a space after it, opens the clipboard. "" turns both off.
        clipboard_alias = "c"

        # Start the launcher when you log in (for the copy installed in an Applications folder).
        launch_at_login = true

        # Where files and folders are searched. "~" is your home folder. A folder here is searched even inside one
        # that ignore skips, like "~/Dropbox" (in ~/Library) or "~/.config".
        folders = ["~"]
        # What to skip: names ("node_modules"), patterns (".*" is every hidden file, "*.photoslibrary"),
        # or paths ("~/Library").
        ignore = [".*", "~/Library", "node_modules", ".build", "*.photoslibrary"]
        # How many folders deep to go.
        max_depth = 6

        [clipboard]
        # How much history to keep: whichever limit is reached first drops the oldest items. Pinned items always stay,
        # and don't count toward max_size_gb.
        max_size_gb = 2
        max_age_days = 30

        [actions]
        # The app "Open in terminal" uses: Terminal, iTerm, Ghostty, Warp…
        terminal = "Terminal"

        [open_with]
        # Which app opens a file type from the launcher: extension or type = app name, bundle id or path.
        # Files of other types open in their default app. For example:
        # md  = "Visual Studio Code"
        # pdf = "Preview"
        # "public.image" = "Pixelmator Pro"

        [open_links]
        # Which app opens a link from the clipboard: URL scheme = app name, bundle id or path. https covers http too,
        # unless http has its own. Other links open in their default app. For example:
        # https  = "Firefox"
        # mailto = "Mail"

        """
}
