import AppKit
import LauncherCore
import Synchronization

/// Watches the general pasteboard and stores each new copy in the clipboard history (`docs/MILESTONE-3.md` step 2).
///
/// macOS has no notification for a new copy, so a timer on a serial queue reads the pasteboard's change count every
/// half second, with leeway so the system can coalesce the wakeups. It stops while the screens sleep or another user's
/// session is in front. Only a change reads the copy; what was on the clipboard at launch isn't recorded.
nonisolated final class ClipboardRecorder: @unchecked Sendable {
    /// How often the change count is read, and how late the system may run it to save wakeups.
    static let interval = DispatchTimeInterval.milliseconds(500)
    static let leeway = DispatchTimeInterval.milliseconds(250)

    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let retention: ClipboardStore.Retention
    private let onRecord: @MainActor @Sendable (Clip, _ removed: [Int64]) -> Void
    /// Whether macOS lets Pith read the clipboard, when that changes (false: denied in Privacy & Security).
    private let onAccessChange: @MainActor @Sendable (_ allowed: Bool) -> Void
    /// The app in front: where a copy that doesn't name its source came from. Updated on the main thread.
    private let frontmostApp = Mutex<String?>(nil)
    private var observers: [any NSObjectProtocol] = []

    // State below is only touched on `queue`.
    private let queue = DispatchQueue(label: "launcher.clipboard.watch", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastChange = 0
    private var running = false
    private var asleep = false
    private var denied = false

    init(
        pasteboard: NSPasteboard = .general, store: ClipboardStore, retention: ClipboardStore.Retention = .standard,
        onRecord: @escaping @MainActor @Sendable (Clip, _ removed: [Int64]) -> Void,
        onAccessChange: @escaping @MainActor @Sendable (_ allowed: Bool) -> Void = { _ in }
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.retention = retention
        self.onRecord = onRecord
        self.onAccessChange = onAccessChange
    }

    /// Starts watching from the clipboard as it is now. Without `timer`, only `check()` reads it (for tests).
    @MainActor func start(timer: Bool = true) {
        let workspace = NSWorkspace.shared
        frontmostApp.withLock { $0 = workspace.frontmostApplication?.bundleIdentifier }
        let center = workspace.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.frontmostApp.withLock { $0 = app?.bundleIdentifier }
            },
            center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: nil) {
                [weak self] _ in self?.setAsleep(true)
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil) {
                [weak self] _ in self?.setAsleep(false)
            },
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: nil) {
                [weak self] _ in self?.setAsleep(true)
            },
            center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: nil) {
                [weak self] _ in self?.setAsleep(false)
            },
        ]
        queue.async { [self] in
            lastChange = pasteboard.changeCount
            running = timer
            updateTimer()
        }
    }

    /// Reads the clipboard if it changed since the last look, and stores the copy. Returns the stored clip, or nil
    /// when nothing changed or the copy isn't kept. The timer does the same on its own.
    func check() async -> Clip? {
        let copy = await withCheckedContinuation { continuation in
            queue.async { [self] in continuation.resume(returning: readIfChanged()) }
        }
        guard let copy else { return nil }
        return await record(copy)
    }

    // MARK: On the queue

    private func setAsleep(_ value: Bool) {
        queue.async { [self] in
            asleep = value
            updateTimer()
        }
    }

    /// Runs the timer while started and awake, and stops it otherwise.
    private func updateTimer() {
        if running && !asleep {
            guard timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: Self.leeway)
            timer.setEventHandler { [weak self] in
                guard let self, let copy = readIfChanged() else { return }
                Task { await self.record(copy) }
            }
            timer.resume()
            self.timer = timer
        } else {
            timer?.cancel()
            timer = nil
        }
    }

    /// The copy on the clipboard, if it changed since the last look and should be kept: not concealed, transient or
    /// auto-generated (decisions 35, 38), and holding text, an image or files.
    private func readIfChanged() -> (content: ClipContent, source: String?, date: Date)? {
        let change = pasteboard.changeCount
        guard change != lastChange else { return nil }
        lastChange = change

        // Denied in Privacy & Security, a read would get nothing: say so instead of failing silently.
        let isDenied = pasteboard.accessBehavior == .alwaysDeny
        if isDenied != denied {
            denied = isDenied
            if isDenied { Log.app.error("Not allowed to read the clipboard: copies aren't recorded") }
            let onAccessChange = self.onAccessChange
            Task { @MainActor in onAccessChange(!isDenied) }
        }
        if isDenied { return nil }

        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }
        // Only the types are read here, so a password's data is never fetched.
        if items.contains(where: { $0.types.contains { ClipReading.skipMarkers.contains($0.rawValue) } }) {
            return nil
        }
        let marked = items.lazy.compactMap { $0.string(forType: .init(ClipReading.sourceMarker)) }.first
        let source = marked ?? frontmostApp.withLock { $0 }
        var representations = items.map { item in
            item.types.filter { ClipReading.types.contains($0.rawValue) }.compactMap { type in
                item.data(forType: type).map { Representation(type: type.rawValue, data: $0) }
            }
        }
        // Rich text with no plain text: the pasteboard converts it, so the clip has text to show and search.
        let types = Set(representations.joined().map(\.type))
        if types.isDisjoint(with: [NSPasteboard.PasteboardType.string.rawValue, "public.utf16-external-plain-text"]),
            !types.isDisjoint(with: ["public.rtf", "com.apple.flat-rtfd", "public.html"]),
            let text = pasteboard.string(forType: .string)
        {
            representations[0].append(
                Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8)))
        }
        return ClipReading.content(of: representations).map { ($0, source, Date()) }
    }

    // MARK: Storing

    private func record(_ copy: (content: ClipContent, source: String?, date: Date)) async -> Clip? {
        do {
            let clip = try await store.add(copy.content, from: copy.source, at: copy.date)
            let removed = try await store.prune(retention, now: copy.date)
            await onRecord(clip, removed)
            return clip
        } catch {
            Log.app.error("Couldn't record a copy: \(error.description, privacy: .public)")
            return nil
        }
    }
}

extension ClipboardStore {
    /// `~/Library/Application Support/pith/clipboard`.
    nonisolated static let defaultFolder = URL.applicationSupportDirectory.appending(path: "pith/clipboard")
}
