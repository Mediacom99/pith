import CoreServices
import Foundation

/// Reports changes anywhere under a set of folders, through FSEvents. Watching stops when it's released.
public final class DirectoryWatcher {
    public struct Event: Sendable, Equatable {
        public let path: String
        public let flags: FSEventStreamEventFlags

        /// Events were dropped or coalesced here: everything under `path` must be looked at again.
        public var mustRescan: Bool {
            let dropped =
                kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
            return flags & FSEventStreamEventFlags(dropped) != 0
        }

        /// The item at `path` was created, removed, or moved in or out: not just changed.
        public var isAddedRemovedOrMoved: Bool {
            let kinds =
                kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed
            return flags & FSEventStreamEventFlags(kinds) != 0
        }
    }

    private let handler: @Sendable ([Event]) -> Void
    private var stream: FSEventStreamRef?

    /// `handler` runs on `queue` with the folders that changed, at most once per `latency` seconds.
    public convenience init?(
        paths: [String],
        latency: TimeInterval = 1,
        queue: DispatchQueue,
        handler: @escaping @Sendable ([String]) -> Void
    ) {
        self.init(paths: paths, latency: latency, queue: queue) { events in handler(events.map(\.path)) }
    }

    /// `handler` runs on `queue` with what changed, at most once per `latency` seconds. With `fileEvents`, each
    /// changed file or folder is reported; without, only the folders containing changes. Changes under `excluding`
    /// (at most 8 paths) are never reported, nor even woken up for.
    public init?(
        paths: [String],
        excluding: [String] = [],
        fileEvents: Bool = false,
        latency: TimeInterval = 1,
        queue: DispatchQueue,
        events handler: @escaping @Sendable ([Event]) -> Void
    ) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            watcher.handler((0..<count).map { Event(path: String(cString: paths[$0]), flags: flags[$0]) })
        }
        let options = fileEvents ? kFSEventStreamCreateFlagFileEvents : kFSEventStreamCreateFlagNone
        guard
            let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(options)
            )
        else { return nil }
        self.stream = stream
        if !excluding.isEmpty { FSEventStreamSetExclusionPaths(stream, Array(excluding.prefix(8)) as CFArray) }
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else { return nil }
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}
