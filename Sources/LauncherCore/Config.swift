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

    // Can't fail: a fixed shortcut in the form `Shortcut` reads, built by every test that makes a `Config`.
    public var launcherHotkey = Shortcut("cmd+p")!
    /// Opens the panel straight in the clipboard (decision 34). Nil when it's off, which leaves the key to apps.
    public var clipboardHotkey = Shortcut("cmd+shift+v")
    /// Pastes the last clip copied, then the one before at each press (decision 64). Nil when it's off.
    public var pasteNextHotkey = Shortcut("ctrl+alt+v")
    /// The keys inside the panel (decision 55).
    public var keys = KeyBindings.defaults
    /// Clipboard History's alias in the launcher (decision 42); followed by a space, it opens the clipboard. Empty
    /// for neither.
    public var clipboardAlias = "c"
    public var emptyState = EmptyState.recent
    /// Applies to the copy installed in an Applications folder (decision 14).
    /// Nil when it isn't known (at launch, with config.toml or this setting wrong): the login item is left alone.
    public var launchAtLogin: Bool? = true
    /// Whether System Settings' pages are among the results (decision 79).
    public var systemSettings = true
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
    /// clipboard's limits, which drop nothing until the file sets them right, and launching at login, which isn't
    /// changed until it does (decision 59).
    static var atLaunch: Config {
        var config = Config()
        config.clipboardMaxSizeGB = nil
        config.clipboardMaxAgeDays = nil
        config.launchAtLogin = nil
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

    /// Written to a new config file: every setting with its default, explained.
    public static let template = """
        # Pith settings. Saved changes apply right away.

        [hotkeys]
        # Opens the launcher from anywhere: modifiers (cmd, shift, alt, ctrl) + one key.
        launcher = "cmd+p"
        # Opens the clipboard history. It takes the key from every app: cmd+shift+v is Paste and Match Style in many,
        # and the clipboard's Paste as Plain Text does the same. "" turns it off.
        clipboard = "cmd+shift+v"
        # Pastes the last clip you copied, then at each press the one before it, down the history. A pause of 10
        # seconds or a new copy starts again from the last one. "" turns it off.
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

        # List System Settings' pages (Wi-Fi, Bluetooth, Displays…) among the results.
        system_settings = true

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
        # Which app opens a file type from the launcher, config.toml included: extension or type = app name, bundle id
        # or path, or an app = a list of them. Files of other types open in their default app. For example:
        # pdf = "Preview"
        # "public.image" = "Pixelmator Pro"
        # "Visual Studio Code" = ["md", "txt", "json", "toml"]

        [open_links]
        # Which app opens a link from the clipboard: URL scheme = app name, bundle id or path. https covers http too,
        # unless http has its own. Other links open in their default app. For example:
        # https  = "Firefox"
        # mailto = "Mail"

        """
}
