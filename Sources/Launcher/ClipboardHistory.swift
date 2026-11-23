import Foundation
import LauncherCore

/// The clipboard history in memory, in step with the store (`docs/MILESTONE-3.md` step 3): loaded at launch, then
/// updated with each copy the recorder stores and each clip retention drops.
final class ClipboardHistory {
    let store: ClipboardStore
    private(set) var index = ClipboardIndex()
    /// Called after every change, so the panel can show it.
    var onChange: (() -> Void)?

    init(store: ClipboardStore) {
        self.store = store
    }

    /// Prunes the history to its limits and loads it. Called once at launch, before the recorder starts, so no copy
    /// can land in between and be lost.
    func load() async {
        do throws(ClipboardStore.Failure) {
            _ = try await store.prune(.standard, now: .now)
            let clips = try await store.load()
            index = await runInBackground(qos: .userInitiated) { ClipboardIndex(clips: clips) }
        } catch {
            Log.app.error("Couldn't load the clipboard history: \(error.description, privacy: .public)")
        }
        onChange?()
    }

    /// A copy the recorder stored, and the clips retention dropped to make room.
    func recorded(_ clip: Clip, removed: [Int64]) {
        index.remove(removed)
        index.insert(clip)
        onChange?()
    }
}
