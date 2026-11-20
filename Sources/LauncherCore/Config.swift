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

    public init() {}

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
    /// default and the rest still apply. A file that isn't valid TOML gives the defaults and one problem.
    public static func parse(_ text: String) -> (config: Config, problems: [String]) {
        var config = Config()
        let tables: [String: [String: TOMLReader.Entry]]
        do {
            tables = try TOMLReader.parse(text)
        } catch {
            return (config, [error.description])
        }

        var problems: [(line: Int, message: String)] = []
        for (table, entries) in tables {
            for (key, entry) in entries {
                let name = table.isEmpty ? key : "\(table).\(key)"
                func problem(_ message: String) { problems.append((entry.line, "line \(entry.line): \(message)")) }
                switch (name, entry.value) {
                case ("hotkeys.launcher", .string(let text)):
                    if let hotkey = Hotkey(text) {
                        config.launcherHotkey = hotkey
                    } else {
                        problem("hotkeys.launcher \"\(text)\" isn't a shortcut like \"cmd+p\"")
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
                case ("hotkeys.launcher", _), ("launcher.empty_state", _), ("actions.terminal", _):
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

        [actions]
        # The app "Open in terminal" uses: Terminal, iTerm, Ghostty, Warp…
        terminal = "Terminal"

        [open_with]
        # Which app opens a file type from the launcher: extension or type = app name, bundle id or path.
        # Files of other types open in their default app. For example:
        # md  = "Visual Studio Code"
        # pdf = "Preview"
        # "public.image" = "Pixelmator Pro"

        """
}
