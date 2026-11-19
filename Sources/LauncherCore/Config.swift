/// The settings in `~/.config/launcher/config.toml`. Every one has a default, so a missing file or key is fine.
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

    public init() {}

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
                case ("hotkeys.launcher", _), ("launcher.empty_state", _):
                    problem("\(name) should be a string in quotes")
                case ("launcher.launch_at_login", _):
                    problem("launcher.launch_at_login should be true or false")
                default:
                    problem("unknown setting \(name)")
                }
            }
        }
        return (config, problems.sorted { $0.line < $1.line }.map(\.message))
    }

    /// Written to a new config file: every setting with its default, explained.
    public static let template = """
        # Launcher settings. Saved changes apply right away.

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

        """
}
