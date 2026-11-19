import LauncherCore

/// What ⌘K offers for an app (FEATURES.md §4.1).
nonisolated enum AppAction: CaseIterable {
    case open
    case reveal
    case quit
    case forceQuit

    var title: String {
        switch self {
        case .open: "Open"
        case .reveal: "Reveal in Finder"
        case .quit: "Quit"
        case .forceQuit: "Force Quit"
        }
    }

    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .reveal: "folder"
        case .quit: "xmark.circle"
        case .forceQuit: "xmark.octagon"
        }
    }

    /// Quit and Force Quit only make sense for a running app.
    static func available(for item: Item, running: Bool) -> [AppAction] {
        item.isApp && running ? allCases : [.open, .reveal]
    }
}

/// The SF Symbols rows use, rendered once by `IconStore`.
nonisolated enum Symbols {
    static let problem = "exclamationmark.triangle"

    static func command(_ command: Command) -> String {
        switch command {
        case .openConfig: "gearshape"
        case .reloadConfig: "arrow.clockwise"
        case .quit: "power"
        }
    }

    static let all = Command.allCases.map(command) + AppAction.allCases.map(\.symbol) + [problem]
}
