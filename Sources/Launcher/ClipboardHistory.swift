import Foundation
import LauncherCore

/// The clipboard history in memory, in step with the store (`docs/MILESTONE-3.md` step 3): loaded at launch, then
/// updated with each copy the recorder stores and each clip retention drops. Loaded again when another program changed
/// the database (decision 73).
final class ClipboardHistory {
    let store: ClipboardStore
    private(set) var index = ClipboardIndex() {
        didSet { changes += 1 }
    }
    /// How many times the index changed: a reload built while it changed is stale.
    private var changes = 0
    /// Called after every change, so the panel can show it.
    var onChange: (() -> Void)?
    /// How much history is kept (`[clipboard]`, decision 37). Nil until the config is read, so nothing is dropped by
    /// limits it doesn't set; a change prunes at once.
    var retention: ClipboardStore.Retention? {
        didSet { if retention != oldValue { Task { await prune() } } }
    }
    private var isLoaded = false
    /// How many copies came in, or clips moved to the top: paste next starts again from the newest when it changes.
    private(set) var copies = 0
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

    /// Loads the history again if another program changed the database since (decision 73), so the list doesn't show
    /// clips that are gone or times that moved. Called as the clipboard opens. A change in Pith while it loads makes it
    /// load again, so the reload never drops a copy that landed meanwhile.
    func reloadIfChangedElsewhere() async {
        guard isLoaded, await store.changedElsewhere() else { return }
        for _ in 0..<3 {
            let before = changes
            do throws(ClipboardStore.Failure) {
                let clips = try await store.load()
                let reloaded = await runInBackground(qos: .userInitiated) { ClipboardIndex(clips: clips) }
                guard changes == before else { continue }
                Log.app.info("The clipboard history changed elsewhere: reloaded \(clips.count) clips")
                index = reloaded
                copies += 1
                onChange?()
                return
            } catch {
                Log.app.error("Couldn't reload the clipboard history: \(error.description, privacy: .public)")
                return
            }
        }
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
            copies += 1
            onChange?()
        } catch {
            Log.app.error("Couldn't move a clip to the top: \(error.description, privacy: .public)")
            if error.isGone { forget(id) }
        }
    }

    /// Drops clip `id`, which the store no longer has (deleted by another program), from the list.
    func forget(_ id: Int64) {
        guard index.position(of: id) != nil else { return }
        remove([id])
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
        copies += 1
        onChange?()
        Task { await prune() }
    }
}
