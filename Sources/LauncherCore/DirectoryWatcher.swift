import CoreServices
import Foundation

/// Reports changes anywhere under a set of folders, through FSEvents. Watching stops when it's released.
public final class DirectoryWatcher {
    private let handler: @Sendable ([String]) -> Void
    private var stream: FSEventStreamRef?

    /// `handler` runs on `queue` with the folders that changed, at most once per `latency` seconds.
    public init?(
        paths: [String],
        latency: TimeInterval = 1,
        queue: DispatchQueue,
        handler: @escaping @Sendable ([String]) -> Void
    ) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<DirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
            watcher.handler((0..<count).map { String(cString: paths[$0]) })
        }
        guard
            let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                paths as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                latency,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)
            )
        else { return nil }
        self.stream = stream
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
