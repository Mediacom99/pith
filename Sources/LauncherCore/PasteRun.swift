import Foundation

/// Paste next (`[hotkeys] paste_next`, decision 64): each press pastes the next clip down the history, from the last
/// one copied, until you stop pressing or the history runs out. The order is the history's at the first press. A pause
/// of `pause`, or a new copy, ends the run, and the next press starts again from the newest.
public struct PasteRun: Sendable, Equatable {
    /// A pause between presses this long ends the run.
    public static let pause: TimeInterval = 10

    /// The clips still to paste, the next one last.
    private var ids: [Int64]
    /// The history's copies when the run started (`ClipboardHistory.copies`): a new copy ends it.
    private let copies: Int
    /// When the key was last pressed, in seconds since boot.
    private var pressed: TimeInterval

    /// A run down `clips`, the history newest first, started by a press at `time`.
    public init(_ clips: [Clip], copies: Int, at time: TimeInterval) {
        ids = clips.reversed().map(\.id)
        self.copies = copies
        pressed = time
    }

    /// Whether a press at `time` goes on with this run: nothing was copied since, and the last press was recent.
    public func goesOn(copies: Int, at time: TimeInterval) -> Bool {
        copies == self.copies && time - pressed < Self.pause
    }

    /// Takes the next clip off the run for a press at `time`, skipping those `index` no longer has (deleted, dropped).
    /// Nil when the history has run out.
    public mutating func next(in index: ClipboardIndex, at time: TimeInterval) -> Clip? {
        pressed = time
        while let id = ids.popLast() {
            if let position = index.position(of: id) { return index.clips[position] }
        }
        return nil
    }
}
