import Foundation

/// Something the launcher can find and open: an app or one of the launcher's own commands.
public struct Item: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case app(URL)
        case command(Command)
    }

    public let kind: Kind
    /// What the row shows and the query matches: an app's localized name, a command's title.
    public let name: String
    /// Stable identity for the history and for matching running apps: an app's bundle path with symlinks resolved,
    /// `command:<name>` for a command.
    public let id: String

    /// `id` defaults to the path as given; the scanner passes the resolved one.
    public init(name: String, appAt url: URL, id: String? = nil) {
        kind = .app(url)
        self.name = name
        self.id = id ?? url.path
    }

    public init(command: Command) {
        kind = .command(command)
        name = command.title
        id = "command:\(command.rawValue)"
    }

    /// The app bundle, for apps.
    public var url: URL? {
        if case .app(let url) = kind { url } else { nil }
    }
}

/// The launcher's own commands, found by searching like apps (FEATURES.md §7).
public enum Command: String, Sendable, CaseIterable {
    case openConfig = "open-config"
    case reloadConfig = "reload-config"
    case quit

    public var title: String {
        switch self {
        case .openConfig: "Open Config"
        case .reloadConfig: "Reload Config"
        case .quit: "Quit Launcher"
        }
    }
}
