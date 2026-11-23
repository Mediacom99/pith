import Foundation
import LauncherCore

/// The clipboard history in memory, in step with the store (`docs/MILESTONE-3.md` step 3): loaded at launch, then
/// updated with each copy the recorder stores and each clip retention drops.
final class ClipboardHistory {
    let store: ClipboardStore
    private(set) var index = ClipboardIndex()
    /// Called after every change, so the panel can show it.
    var onChange: (() -> Void)?
    /// How much history is kept (`[clipboard]`, decision 37). Nil until the config is read, so nothing is dropped by
    /// limits it doesn't set; a change prunes at once.
    var retention: ClipboardStore.Retention? {
        didSet { if retention != oldValue { Task { await prune() } } }
    }
    private var isLoaded = false
    /// Clips removed (cleared, deleted, pruned): a copy whose notice comes in after its removal isn't put back. Ids are
    /// never reused.
    private var removed: Set<Int64> = []

    init(store: ClipboardStore) {
        self.store = store
    }

    /// Loads the history and prunes it to its limits. Called once at launch, before the recorder starts, so no copy
    /// can land in between and be lost.
    func load() async {
        do throws(ClipboardStore.Failure) {
            let clips = try await store.load()
            index = await runInBackground(qos: .userInitiated) { ClipboardIndex(clips: clips) }
        } catch {
            Log.app.error("Couldn't load the clipboard history: \(error.description, privacy: .public)")
        }
        isLoaded = true
        await prune()
        onChange?()
    }

    /// Drops what `retention` doesn't keep, oldest unpinned first. Waits for the load, so the index it updates is
    /// the one on screen.
    func prune() async {
        guard isLoaded, let retention else { return }
        do throws(ClipboardStore.Failure) {
            let pruned = try await store.prune(retention, now: .now)
            guard !pruned.isEmpty else { return }
            remove(pruned)
        } catch {
            Log.app.error("Couldn't prune the clipboard history: \(error.description, privacy: .public)")
        }
    }

    /// Deletes every clip that isn't pinned (Clear Clipboard History).
    func clear() async throws(ClipboardStore.Failure) {
        remove(try await store.clear())
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
            remove([id])
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

    private func remove(_ ids: [Int64]) {
        removed.formUnion(ids)
        index.remove(ids)
        onChange?()
    }

    /// A copy the recorder stored; older clips may have to go to make room.
    func recorded(_ clip: Clip) {
        guard !removed.contains(clip.id) else { return }
        index.insert(clip)
        onChange?()
        Task { await prune() }
    }
}
