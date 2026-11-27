import AppKit
import LauncherCore

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
        case .settingsPage, .command: []
        }
    }
}

/// What ⌘K offers on a clip (docs/BRIEF-CLIPBOARD.md §6), in the brief's order.
nonisolated enum ClipAction: CaseIterable, Sendable {
    case paste, copy, pastePlainText, openLink, reveal, save, pin, unpin, delete

    /// The actions for `clip`. Paste needs Accessibility access; without it the plain-text action copies.
    static func available(for clip: Clip, canPaste: Bool) -> [ClipAction] {
        var actions: [ClipAction] = canPaste ? [.paste, .copy] : [.copy]
        switch clip.kind {
        case .richText: actions += [.pastePlainText, .save]
        case .text: actions.append(.save)
        case .link: actions.append(.openLink)
        case .image: actions.append(.save)
        case .files: actions.append(.reveal)
        }
        return actions + [clip.pinned ? .unpin : .pin, .delete]
    }

    /// `linkApp`: the app that opens a link, once known ("Open in Safari").
    func title(canPaste: Bool, linkApp: String?) -> String {
        switch self {
        case .paste: "Paste"
        case .copy: "Copy to Clipboard"
        case .pastePlainText: canPaste ? "Paste as Plain Text" : "Copy as Plain Text"
        case .openLink: linkApp.map { "Open in \($0)" } ?? "Open Link"
        case .reveal: "Reveal in Finder"
        case .save: "Save as File"
        case .pin: "Pin"
        case .unpin: "Unpin"
        case .delete: "Delete"
        }
    }

    var symbol: String {
        switch self {
        case .paste: "arrow.down.doc"
        case .copy: "doc.on.doc"
        case .pastePlainText: "textformat"
        case .openLink: "arrow.up.forward.app"
        case .reveal: "folder"
        case .save: "square.and.arrow.down"
        case .pin: "pin"
        case .unpin: "pin.slash"
        case .delete: "trash"
        }
    }

    /// Delete waiting for its second press, as Force Quit does (decisions 28, 74): on a pinned clip, or run by a
    /// shortcut.
    static func deleteConfirmation(pinned: Bool) -> String {
        pinned ? "Press ⏎ again to delete this pinned clip" : "Press ⏎ again to delete this clip"
    }
}

/// Where Save as File puts a clip (decision 39): "Clipboard 2026-11-23 at 14.05.png", then "… 2.png" and up when taken.
nonisolated enum ClipFiles {
    static func destination(in folder: URL, at date: Date, extension fileExtension: String) -> URL {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        let name = "Clipboard \(format.string(from: date))"
        var candidate = folder.appending(path: "\(name).\(fileExtension)")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(name) \(number).\(fileExtension)")
            number += 1
        }
        return candidate
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
        case .checkForUpdates: "arrow.triangle.2.circlepath"
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
