import Carbon.HIToolbox

/// What a key does in the panel, named as in `[keys]` (decision 55).
public enum PanelKey: String, Sendable, CaseIterable {
    case up, down
    /// ⏎: opens the selected item, runs the selected action, pastes the selected clip.
    case open
    /// ⌘K: the selected item's actions, or back to the search.
    case actions
    /// ⎋: back one level, or close.
    case back
    /// ⌘Y and Space: Quick Look.
    case preview
    /// ⌘Q, ⌘W, ⌘E…: in an actions list, the nth runs its nth action (decision 43).
    case runActions = "run_actions"
    /// ⌫: from the clipboard back to the launcher.
    case toLauncher = "to_launcher"

    var defaults: [String] {
        switch self {
        case .up: ["up", "ctrl+k"]
        case .down: ["down", "ctrl+j"]
        case .open: ["return"]
        case .actions: ["cmd+k"]
        case .back: ["escape"]
        case .preview: ["cmd+y", "space"]
        case .runActions: ["cmd+q", "cmd+w", "cmd+e", "cmd+r", "cmd+t", "cmd+y", "cmd+u"]
        case .toLauncher: ["backspace"]
        }
    }

    /// Whether the panel can't do without it: it keeps at least one key.
    var isRequired: Bool { self == .open || self == .back }

    /// Whether this key and `other` can share a shortcut. Inside an actions list `run_actions` comes first, and
    /// `to_launcher` never acts there, so neither clashes with it; ⌘Y is both an action and Quick Look by default.
    func canShare(with other: PanelKey) -> Bool {
        let pair: Set = [self, other]
        return pair == [.runActions, .preview] || pair == [.runActions, .toLauncher]
    }
}

/// The panel's keys: each `PanelKey`'s shortcuts, the first being the one the panel shows.
public struct KeyBindings: Sendable, Equatable {
    /// Only `run_actions` has holes, where a shortcut was left out, so the ones after it keep their places.
    private var table: [PanelKey: [Shortcut?]]

    public static let defaults = KeyBindings(
        table: Dictionary(uniqueKeysWithValues: PanelKey.allCases.map { ($0, $0.defaults.map(Shortcut.init)) }))

    /// The shortcuts for `key`, the one to show first.
    public subscript(key: PanelKey) -> [Shortcut] {
        table[key, default: []].compactMap(\.self)
    }

    /// `run_actions`: the nth runs an actions list's nth action. Nil where a shortcut was left out.
    public var runActions: [Shortcut?] { table[.runActions, default: []] }

    /// The fixed editing keys of the search field, which no setting may take.
    static let editingKeys: [(shortcut: Shortcut, name: String)] = [
        ("cmd+x", "Cut"), ("cmd+c", "Copy"), ("cmd+v", "Paste"), ("cmd+a", "Select All"), ("cmd+z", "Undo"),
        ("shift+cmd+z", "Redo"),
    ].map { (Shortcut($0)!, $1) }

    /// The bindings from what `[keys]` says, in file order: every key not written keeps its default. A shortcut
    /// already taken (by an earlier setting, a hotkey or an editing key) is left out of the later setting, with a
    /// problem; a default that a written setting took is left out quietly. `open` and `back` left with no key get their
    /// default back, and the panel looks them up first.
    static func resolve(
        written: [(key: PanelKey, line: Int, shortcuts: [Shortcut])], hotkeys: [(name: String, shortcut: Shortcut)]
    ) -> (bindings: KeyBindings, problems: [(line: Int, message: String)]) {
        var problems: [(line: Int, message: String)] = []
        var owners: [Shortcut: [PanelKey]] = [:]
        var table: [PanelKey: [Shortcut?]] = [:]
        // `open` or `back` turned off gets its default back: reserved first, so another setting, wherever it is, can't
        // take a key it would never fire on.
        for key in PanelKey.allCases
        where key.isRequired && written.contains(where: { $0.key == key && $0.shortcuts.isEmpty }) {
            for shortcut in key.defaults.compactMap(Shortcut.init) { owners[shortcut, default: []].append(key) }
        }
        let defaults = PanelKey.allCases.filter { key in !written.contains { $0.key == key } }.map {
            (key: $0, line: Int?.none, shortcuts: $0.defaults.compactMap(Shortcut.init))
        }
        let settings = written.sorted { $0.line < $1.line }.map { ($0.key, Optional($0.line), $0.shortcuts) } + defaults
        for (key, line, shortcuts) in settings {
            var kept: [Shortcut?] = []
            for shortcut in shortcuts {
                let taken: String? =
                    if let hotkey = hotkeys.first(where: { $0.shortcut == shortcut }) {
                        "is hotkeys.\(hotkey.name)"
                    } else if let editing = editingKeys.first(where: { $0.shortcut == shortcut }) {
                        "is \(editing.name) in the search field"
                    } else if let owner = owners[shortcut]?.first(where: { !$0.canShare(with: key) }) {
                        owner == key ? "is there twice" : "is already keys.\(owner.rawValue)"
                    } else {
                        nil
                    }
                if let taken {
                    if let line {
                        problems.append(
                            (line, "line \(line): keys.\(key.rawValue) \"\(shortcut)\" \(taken), so it's left out"))
                    }
                    // A hole keeps the later actions on their shortcuts; elsewhere a list just closes up.
                    if key == .runActions { kept.append(nil) }
                    continue
                }
                owners[shortcut, default: []].append(key)
                kept.append(shortcut)
            }
            // ⏎ and ⎋ can't be turned off: the panel would have no way to open anything, or to go back.
            if key.isRequired, kept.isEmpty {
                kept = key.defaults.map(Shortcut.init)
                for case let shortcut? in kept where owners[shortcut]?.contains(key) != true {
                    owners[shortcut, default: []].append(key)
                }
                let keys = key.defaults.map { "\"\($0)\"" }.joined(separator: ", ")
                if let line {
                    problems.append((line, "line \(line): keys.\(key.rawValue) needs a key, so it's \(keys)"))
                }
            }
            table[key] = kept
        }
        return (KeyBindings(table: table), problems)
    }
}
