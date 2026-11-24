import Foundation

/// What Quick Look shows when the selection changes. It shows the file it was opened on; a key, a click or typing
/// that moves the selection takes it to the new one, and a list refreshed by something else (a copy, the apps
/// changing) closes it rather than switch it to a file nobody chose.
enum PreviewTarget {
    enum Change: Equatable {
        case keep
        case show(URL)
        case close
    }

    /// `showing`: the file on the preview, nil when it's closed. `selected`: the selected row's file, if any.
    static func change(showing: URL?, selected: URL?, byUser: Bool) -> Change {
        guard let showing, selected != showing else { return .keep }
        if byUser, let selected { return .show(selected) }
        return .close
    }
}
