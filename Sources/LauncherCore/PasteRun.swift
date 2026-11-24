/// Paste next (`[hotkeys] paste_next`, decision 63): after a clip is pasted from the clipboard, the clips copied after
/// it, which the hotkey pastes one at a time in the order they were copied, up to the newest. The order is the
/// history's when the clip was pasted, since each paste moves its clip to the top; a copy made meanwhile doesn't join.
public struct PasteRun: Sendable, Equatable {
    /// The clips still to paste, the next one last.
    private var ids: [Int64]

    /// The run after `id` in `clips`, the history newest first: every clip above it. None when it isn't there.
    public init(after id: Int64, in clips: [Clip]) {
        guard let position = clips.firstIndex(where: { $0.id == id }) else {
            ids = []
            return
        }
        ids = clips[..<position].map(\.id)
    }

    public var isEmpty: Bool { ids.isEmpty }

    /// Takes the next clip off the run, skipping those `index` no longer has (deleted, dropped). Nil when it's over.
    public mutating func next(in index: ClipboardIndex) -> Clip? {
        while let id = ids.popLast() {
            if let position = index.position(of: id) { return index.clips[position] }
        }
        return nil
    }
}
