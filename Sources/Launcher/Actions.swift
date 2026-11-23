import AppKit
import LauncherCore
import UniformTypeIdentifiers

/// What ⌘K offers for an item (FEATURES.md §4.1–4.3).
nonisolated enum Action: CaseIterable {
    case open
    case reveal
    case copyPath
    case openWith
    case openInTerminal
    case copyItem
    case zip
    case trash
    case quit
    case forceQuit

    func title(for item: Item) -> String {
        let isFolder = if case .folder = item.kind { true } else { false }
        return switch self {
        case .open: isFolder ? "Open in Finder" : "Open"
        case .reveal: "Reveal in Finder"
        case .copyPath: "Copy Path"
        case .openWith: "Open With…"
        case .openInTerminal: "Open in Terminal"
        case .copyItem: isFolder ? "Copy Folder" : "Copy File"
        case .zip: "Zip"
        case .trash: "Move to Trash"
        case .quit: "Quit"
        case .forceQuit: "Force Quit"
        }
    }

    /// What the Force Quit row says while it waits for its second ⏎ (decision 28).
    static func forceQuitConfirmation(for item: Item) -> String {
        "Press ⏎ again to force quit \(item.name)"
    }

    var symbol: String {
        switch self {
        case .open: "arrow.up.forward.app"
        case .reveal: "folder"
        case .copyPath: "link"
        case .openWith: "square.grid.2x2"
        case .openInTerminal: "terminal"
        case .copyItem: "doc.on.doc"
        case .zip: "doc.zipper"
        case .trash: "trash"
        case .quit: "xmark.circle"
        case .forceQuit: "xmark.octagon"
        }
    }

    /// Quit and Force Quit only for a running app; Open With… for files; Open in Terminal for folders.
    static func available(for item: Item, running: Bool) -> [Action] {
        switch item.kind {
        case .app: running ? [.open, .reveal, .quit, .forceQuit] : [.open, .reveal]
        case .file: [.open, .reveal, .copyPath, .openWith, .copyItem, .zip, .trash]
        case .folder: [.open, .reveal, .copyPath, .openInTerminal, .copyItem, .zip, .trash]
        case .command: []
        }
    }
}

/// The SF Symbols rows use, rendered once by `IconStore`.
nonisolated enum Symbols {
    static let problem = "exclamationmark.triangle"

    static func command(_ command: Command) -> String {
        switch command {
        case .clipboard: clipboard
        case .pauseClipboard: paused
        case .resumeClipboard: "play.circle"
        case .clearClipboard: "trash"
        case .installUpdate: "arrow.down.circle"
        case .openConfig: "gearshape"
        case .reloadConfig: "arrow.clockwise"
        case .quit: "power"
        }
    }

    /// The clipboard's: a text or link with no known source, a link and the empty history on the tile, and recording
    /// paused.
    static let text = "text.alignleft"
    static let link = "link"
    static let clipboard = "doc.on.clipboard"
    static let paused = "pause.circle"

    static let all =
        Command.allCases.map(command) + Action.allCases.map(\.symbol) + ClipAction.allCases.map(\.symbol)
        + [problem, text, link, clipboard, paused]

    /// Every symbol in the colors and sizes the panel shows it: all in the rows, quiet; a problem's in orange and Force
    /// Quit's in red too; on the tile, the commands' and a problem's.
    static let rendered: [(name: String, tint: SymbolTint, size: IconSize)] =
        all.map { ($0, .quiet, .row) }
        + [(problem, .warning, .row), (Action.forceQuit.symbol, .danger, .row), (problem, .warning, .tile)]
        + [(ClipAction.delete.symbol, .danger, .row), (command(.clearClipboard), .danger, .row)]
        + Command.allCases.map { (command($0), .quiet, .tile) }
        + [text, link, clipboard, paused].map { ($0, .quiet, .tile) }
}

/// Turns the apps named in config.toml into app bundles, and picks the app `[open_with]` sets for a file. Asks
/// LaunchServices, so call it on a worker.
nonisolated enum AppResolver {
    /// An installed app, as the index knows it: its names (as listed, and its file name) and bundle.
    struct App: Sendable {
        let names: [String]
        let url: URL
    }

    /// An app given by name (as the launcher lists it, any case), bundle id (`com.microsoft.VSCode`) or path.
    static func resolve(_ spec: String, among apps: [App]) -> URL? {
        if spec.hasPrefix("/") || spec.hasPrefix("~") {
            let path = (spec as NSString).expandingTildeInPath
            return path.hasSuffix(".app") && FileManager.default.fileExists(atPath: path) ? URL(filePath: path) : nil
        }
        if let app = apps.first(where: { $0.names.contains { $0.caseInsensitiveCompare(spec) == .orderedSame } }) {
            return app.url
        }
        return spec.contains(".") && !spec.contains(" ")
            ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: spec) : nil
    }

    /// `[open_links]`'s apps by URL scheme, and a problem for each one that isn't found. `https` covers `http` too,
    /// unless `http` has its own.
    static func links(_ openLinks: [String: String], among apps: [App]) -> (apps: [String: URL], problems: [String]) {
        var found: [String: URL] = [:]
        var problems: [String] = []
        for (scheme, spec) in openLinks.sorted(by: { $0.key < $1.key }) {
            if let app = resolve(spec, among: apps) {
                found[scheme] = app
            } else {
                problems.append("open_links.\(scheme): can't find the app \"\(spec)\"")
            }
        }
        if openLinks["http"] == nil, let https = found["https"] { found["http"] = https }
        return (found, problems)
    }

    /// The app `[open_with]` sets for `file`: by its extension, else by the most specific type it conforms to.
    static func app(forFile file: URL, openWith: [String: URL]) -> URL? {
        let ext = file.pathExtension.lowercased()
        if let app = openWith[ext] { return app }
        guard let type = UTType(filenameExtension: ext) else { return nil }
        let matches = openWith.compactMap { key, app -> (type: UTType, app: URL)? in
            guard key.contains("."), let declared = UTType(key), type.conforms(to: declared) else { return nil }
            return (declared, app)
        }
        // The most specific: one that conforms to all the others (public.png before public.image).
        let specific = matches.first { candidate in matches.allSatisfy { candidate.type.conforms(to: $0.type) } }
        return specific?.app ?? matches.first?.app
    }

    /// The apps that can open `file`, best first, as items to list.
    static func apps(toOpen file: URL, among apps: [App]) -> [Item] {
        NSWorkspace.shared.urlsForApplications(toOpen: file).map { url in
            let known = apps.first { $0.url.standardizedFileURL == url.standardizedFileURL }?.names.first
            let name = known ?? url.deletingPathExtension().lastPathComponent
            return Item(name: name, appAt: url)
        }
    }
}
