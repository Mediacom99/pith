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

    func setPinned(_ pinned: Bool, for id: Int64) async {
        do throws(ClipboardStore.Failure) {
            try await store.setPinned(pinned, for: id)
            index.setPinned(pinned, for: id)
            onChange?()
        } catch {
            Log.app.error("Couldn't pin a clip: \(error.description, privacy: .public)")
        }
    }

    func delete(_ id: Int64) async {
        do throws(ClipboardStore.Failure) {
            try await store.delete(id)
            index.remove([id])
            onChange?()
        } catch {
            Log.app.error("Couldn't delete a clip: \(error.description, privacy: .public)")
        }
    }

    /// Puts clip `id` back at the top, as a copy would.
    func moveToTop(_ id: Int64, at date: Date = .now) async {
        do throws(ClipboardStore.Failure) {
            index.insert(try await store.touch(id, at: date))
            onChange?()
        } catch {
            Log.app.error("Couldn't move a clip to the top: \(error.description, privacy: .public)")
        }
    }

    /// A copy the recorder stored, and the clips retention dropped to make room.
    func recorded(_ clip: Clip, removed: [Int64]) {
        index.remove(removed)
        index.insert(clip)
        onChange?()
    }
}
