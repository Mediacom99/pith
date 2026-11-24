import LauncherCore

/// One line in the list.
enum Row: Equatable {
    case item(Item)
    /// A ⌘K action for the item the actions list is for.
    case action(Action)
    /// Something wrong in config.toml; ⏎ opens the file.
    case problem(String)
    /// An entry of the clipboard history.
    case clip(Clip)
    /// A ⌘K action for the clip the actions list is for.
    case clipAction(ClipAction)
    /// Above the clipboard's clips: recording paused, or the clipboard not readable.
    case notice(ClipboardNotice)
}

/// A list shown in place of the search, from ⌘K.
enum Sublist: Equatable {
    /// An item's actions.
    case actions(Item)
    /// The apps that can open a file, from Open With….
    case openWith(file: Item, apps: [Item])
    /// A clip's actions.
    case clipActions(Clip)
}
