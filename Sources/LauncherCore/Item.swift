import Foundation

/// Something the launcher can find and open: an app, a file, a folder, or one of the launcher's own commands.
public struct Item: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case app(URL)
        case file(URL)
        case folder(URL)
        case command(Command)
    }

    public let kind: Kind
    /// What the row shows and the query matches: an app's localized name, a file's or folder's name, a command's
    /// title.
    public let name: String
    /// Stable identity for the history and for matching running apps: an app's bundle path with symlinks resolved,
    /// `file:<path>` or `folder:<path>`, `command:<name>` for a command.
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

    public init(path: String, isFolder: Bool) {
        let url = URL(filePath: path, directoryHint: isFolder ? .isDirectory : .notDirectory)
        kind = isFolder ? .folder(url) : .file(url)
        name = url.lastPathComponent
        id = (isFolder ? Self.folderPrefix : Self.filePrefix) + path
    }

    /// The item a history id stands for, when it's a file or folder.
    public init?(fileID id: String) {
        if id.hasPrefix(Self.filePrefix) {
            self.init(path: String(id.dropFirst(Self.filePrefix.count)), isFolder: false)
        } else if id.hasPrefix(Self.folderPrefix) {
            self.init(path: String(id.dropFirst(Self.folderPrefix.count)), isFolder: true)
        } else {
            return nil
        }
    }

    static let filePrefix = "file:"
    static let folderPrefix = "folder:"

    /// Where it is on disk: an app bundle, a file or a folder.
    public var url: URL? {
        switch kind {
        case .app(let url), .file(let url), .folder(let url): url
        case .command: nil
        }
    }

    public var isApp: Bool {
        if case .app = kind { true } else { false }
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
