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

    public var launcherHotkey = Hotkey("cmd+p")!
    /// Opens the panel straight in the clipboard (decision 34).
    public var clipboardHotkey = Hotkey("cmd+shift+v")!
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
    /// clips.
    public var clipboardMaxSizeGB = 2.0
    public var clipboardMaxAgeDays = 30

    public init() {}

    /// The clipboard's limits, as the store applies them.
    public var clipboardRetention: ClipboardStore.Retention {
        ClipboardStore.Retention(
            maxBytes: Int(clipboardMaxSizeGB * 1_000_000_000), maxAge: TimeInterval(clipboardMaxAgeDays) * 86_400)
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
        return FileRules(roots: roots, ignore: IgnoreRules(ignore, home: home), maxDepth: maxDepth)
    }

    /// The settings in `text`, plus a problem for every setting that's wrong or unknown. A wrong setting keeps its
    /// default and the rest still apply. A file that isn't valid TOML gives the defaults and one problem, which says so.
    public static func parse(_ text: String) -> (config: Config, problems: [String]) {
        var config = Config()
        let tables: [String: [String: TOMLReader.Entry]]
        do {
            tables = try TOMLReader.parse(text)
        } catch {
            return (config, ["\(error.description), so every setting is at its default"])
        }

        var problems: [(line: Int, message: String)] = []
        for (table, entries) in tables {
            for (key, entry) in entries {
                let name = table.isEmpty ? key : "\(table).\(key)"
                func problem(_ message: String) { problems.append((entry.line, "line \(entry.line): \(message)")) }
                func size(_ gigabytes: Double, as written: String) {
                    if gigabytes > 0, gigabytes <= 1_000 {
                        config.clipboardMaxSizeGB = gigabytes
                    } else {
                        problem("clipboard.max_size_gb is \(written), expected more than 0 and at most 1000")
                    }
                }
                switch (name, entry.value) {
                case ("hotkeys.launcher", .string(let text)), ("hotkeys.clipboard", .string(let text)):
                    if let hotkey = Hotkey(text) {
                        if key == "launcher" { config.launcherHotkey = hotkey } else { config.clipboardHotkey = hotkey }
                    } else {
                        problem("\(name) \"\(text)\" isn't a shortcut like \"cmd+p\"")
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
                    config.openWith[key.lowercased().trimmingPrefix(".").description] = app
                case (_, _) where table == "open_with":
                    problem("open_with.\(key) should be an app name in quotes")
                case (_, .string(let app)) where table == "open_links":
                    // "https:" and "https://" mean "https" too.
                    var scheme = key.lowercased()
                    while scheme.hasSuffix(":") || scheme.hasSuffix("/") { scheme.removeLast() }
                    if let first = scheme.first, first.isASCII, first.isLetter,
                        scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) })
                    {
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
                case ("hotkeys.launcher", _), ("hotkeys.clipboard", _), ("launcher.empty_state", _),
                    ("actions.terminal", _):
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
        return (config, problems.sorted { $0.line < $1.line }.map(\.message))
    }

    /// Written to a new config file: every setting with its default, explained.
    public static let template = """
        # Pith settings. Saved changes apply right away.

        [hotkeys]
        # Opens the launcher from anywhere: modifiers (cmd, shift, alt, ctrl) + one key.
        launcher = "cmd+p"
        # Opens the clipboard history. It takes the key from every app: cmd+shift+v is Paste and Match Style in many,
        # and the clipboard's Paste as Plain Text does the same.
        clipboard = "cmd+shift+v"

        [launcher]
        # What the launcher shows before you type:
        #   "recent"   what you opened last, newest first
        #   "running"  open apps, most recently used first
        #   "none"     just the search bar
        empty_state = "recent"

        # Start the launcher when you log in (for the copy installed in an Applications folder).
        launch_at_login = true

        # Where files and folders are searched. "~" is your home folder.
        folders = ["~"]
        # What to skip: names ("node_modules"), patterns (".*" is every hidden file, "*.photoslibrary"),
        # or paths ("~/Library").
        ignore = [".*", "~/Library", "node_modules", ".build", "*.photoslibrary"]
        # How many folders deep to go.
        max_depth = 6

        [clipboard]
        # How much history to keep: whichever limit is reached first drops the oldest items. Pinned items always stay.
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
