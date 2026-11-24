import AppKit
import LauncherCore
import UniformTypeIdentifiers
import os

nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "pith"
    static let app = Logger(subsystem: subsystem, category: "app")
    /// Latencies, at debug level: next to free unless someone is streaming them (`make logs`).
    static let perf = Logger(subsystem: subsystem, category: "perf")

    /// Logs the time from an input event until now, split into its phases. All times are in seconds since boot, the
    /// clock of event timestamps: `event` is the key press, `handled` when our code started on it, `updated` when the
    /// views were updated, and now is when they're drawn.
    static func latency(_ label: String, event: TimeInterval, handled: TimeInterval, updated: TimeInterval) {
        let drawn = ProcessInfo.processInfo.systemUptime
        let total = (drawn - event) * 1000
        let delivery = (handled - event) * 1000
        let update = (updated - handled) * 1000
        let draw = (drawn - updated) * 1000
        perf.debug(
            "\(label, privacy: .public): \(total, format: .fixed(precision: 2)) ms = delivery \(delivery, format: .fixed(precision: 2)) + update \(update, format: .fixed(precision: 2)) + draw \(draw, format: .fixed(precision: 2))"
        )
    }
}

/// Wires the pieces together: builds the panel up front, applies the config (hotkey, empty state, login item), runs
/// the launcher's commands and keeps the index fresh.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private let history = HistoryStore()
    private let hotkeys = GlobalHotkeys()
    private let notifier = Notifier()
    private let updater = Updater()
    private lazy var files = FileSearchEngine { [weak self] removed in
        // Hashed here, on the engine's queue: a deleted build folder can be tens of thousands of paths.
        let removed = Set(removed)
        Task { @MainActor in self?.history.forget(paths: removed) }
    }
    private let clipboard = ClipboardHistory(store: ClipboardStore(folder: ClipboardStore.defaultFolder))
    private lazy var recorder = ClipboardRecorder(
        store: clipboard.store,
        onRecord: { [weak self] clip in self?.clipboard.recorded(clip) },
        onAccessChange: { [weak self] allowed in
            self?.canReadClipboard = allowed
            self?.publishClipboardNotices()
        })
    /// What the clipboard says above its clips: macOS denies reading it, paste lacks Accessibility access, or
    /// recording is paused (decision 44).
    private var canReadClipboard = true
    private var isRecordingPaused = false
    private var askedForAccessibility = false
    private var fileRules: FileRules?
    private var panel: LauncherPanel?
    private var appsWatcher: DirectoryWatcher?
    private var indexGeneration = 0
    private var hasAppliedConfig = false
    /// Apps in config.toml that don't resolve to an installed app.
    private var appProblems: [String] = []
    private var resolveGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Built now, so the hotkey only has to show it.
        let launcher = LauncherViewController(history: history, running: RunningApps(), files: files)
        launcher.runCommand = { [weak self] in self?.run($0) }
        launcher.clipboard = clipboard
        launcher.resolveNotice = { [weak self] notice in
            switch notice {
            case .cannotRead:
                // Privacy & Security, where macOS lists the apps that may read the clipboard.
                if let settings = Accessibility.clipboardSettings { NSWorkspace.shared.open(settings) }
            case .needsAccessibility:
                if let settings = Accessibility.settings { NSWorkspace.shared.open(settings) }
            case .paused:
                self?.setRecordingPaused(false)
            }
        }
        launcher.onShowClipboard = { [weak self] in self?.checkAccessibility() }
        launcher.askForAccessibility = { [weak self] in
            // Once per launch: macOS's request, then the setting is a notice away.
            guard let self, !askedForAccessibility else { return }
            askedForAccessibility = true
            Task { await runInBackground(qos: .userInitiated) { Accessibility.ask() } }
        }
        launcher.notifier = notifier
        notifier.install()
        panel = LauncherPanel(launcher: launcher)
        panel?.onDismiss = { [weak self] in
            // After the event that closed the panel, so an open or a paste goes first.
            Task { self?.updater.checkIfDue() }
        }
        updater.onReady = { [weak self] version in self?.panel?.launcher.readyUpdate = version }
        updater.onResult = { [weak self] result in self?.notifier.update(result) }
        updater.reportLastUpdate()
        launcher.checksForUpdates = Updater.isEnabled
        checkAccessibility()

        configStore.onChange = { [weak self] previous in self?.apply(previous: previous) }
        Task {
            // The history is in before the config registers the hotkey, so nothing is opened before it loads.
            await history.load()
            await configStore.start()
        }

        // The clipboard history is loaded before the recorder starts, so no copy can slip in between, and a pause
        // saved before a relaunch holds from the start.
        Task {
            await clipboard.load()
            if await clipboard.store.isPaused() { setRecordingPaused(true, save: false) }
            await recorder.start()
        }

        rebuildIndex()
        appsWatcher = DirectoryWatcher(paths: AppScanner.defaultRoots.map(\.path), queue: .main) { [weak self] paths in
            guard paths.contains(where: AppScanner.affectsIndex) else { return }
            Task { @MainActor in self?.rebuildIndex() }
        }
    }

    /// Opening Pith.app while it runs (Finder, Spotlight, `open`) opens the launcher: the way in when its hotkey doesn't
    /// fire, taken by a system shortcut.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        history.flush()
    }

    private func apply(previous: Config) {
        guard let panel else { return }
        let config = configStore.config

        hotkeys.apply([
            ("launcher", config.launcherHotkey, { [weak panel] in panel?.toggle(pressedAt: $0) }),
            ("clipboard", config.clipboardHotkey, { [weak panel] in panel?.toggleClipboard(pressedAt: $0) }),
            ("paste_next", config.pasteNextHotkey, { [weak panel] in panel?.pasteNext(pressedAt: $0) }),
        ])
        panel.launcher.clipboardHotkey = hotkeys.current("clipboard")?.symbols
        panel.launcher.keys = config.keys
        panel.launcher.clipboardAlias = config.clipboardAlias
        panel.launcher.emptyState = config.emptyState
        clipboard.retention = config.clipboardRetention
        publishProblems()
        resolveApps()

        let rules = config.fileRules()
        if rules != fileRules {
            fileRules = rules
            Task { [files] in await files.rebuild(rules) }
        }

        if !hasAppliedConfig || previous.launchAtLogin != config.launchAtLogin {
            LoginItem.update(enabled: config.launchAtLogin)
        }
        hasAppliedConfig = true
    }

    /// Asks on a worker whether Pith may press ⌘V, at launch and each time the clipboard opens: access can be given in
    /// System Settings at any time.
    private func checkAccessibility() {
        Task {
            let allowed = await runInBackground(qos: .userInitiated) { Accessibility.isAllowed }
            panel?.launcher.canPaste = allowed
            publishClipboardNotices()
        }
    }

    private func publishClipboardNotices() {
        guard let launcher = panel?.launcher else { return }
        var notices: [ClipboardNotice] = []
        if !canReadClipboard { notices.append(.cannotRead) }
        if !launcher.canPaste { notices.append(.needsAccessibility) }
        if isRecordingPaused { notices.append(.paused) }
        launcher.clipboardNotices = notices
    }

    /// Pauses or resumes recording, and saves it so a relaunch keeps it (decision 44). The launcher then lists the
    /// command that undoes it (decision 45).
    private func setRecordingPaused(_ paused: Bool, save: Bool = true) {
        isRecordingPaused = paused
        recorder.setPaused(paused)
        panel?.launcher.hiddenCommands = [paused ? .pauseClipboard : .resumeClipboard]
        publishClipboardNotices()
        guard save else { return }
        let store = clipboard.store
        Task {
            do throws(ClipboardStore.Failure) {
                try await store.setPaused(paused)
            } catch {
                Log.app.error("\(error.description, privacy: .public)")
            }
        }
    }

    /// Clear Clipboard History, after its second ⏎: every clip but the pinned ones.
    private func clearClipboard() {
        Task {
            do throws(ClipboardStore.Failure) {
                try await clipboard.clear()
            } catch {
                Log.app.error("Couldn't clear the clipboard history: \(error.description, privacy: .public)")
                notifier.failed("Couldn't clear the clipboard history", item: nil, reason: error.description)
            }
        }
    }

    private func publishProblems() {
        panel?.launcher.problems = configStore.problems + hotkeys.problems + appProblems
    }

    /// Resolves the apps config.toml names (`[open_with]`, `[open_links]`, the terminal) on a worker, once the index
    /// knows the installed apps; names that match no app become problems.
    private func resolveApps() {
        guard let launcher = panel?.launcher, !launcher.index.items.isEmpty else { return }
        let config = configStore.config
        let apps = launcher.knownApps
        resolveGeneration += 1
        let generation = resolveGeneration
        Task {
            let (openWith, openLinks, terminal, problems) = await runInBackground(qos: .utility) {
                var problems: [String] = []
                var openWith: [String: URL] = [:]
                for (key, spec) in config.openWith.sorted(by: { $0.key < $1.key }) {
                    if key.contains("."), UTType(key) == nil {
                        problems.append("open_with \"\(key)\" isn't a known file type")
                    } else if let app = AppResolver.resolve(spec, among: apps) {
                        openWith[key] = app
                    } else {
                        problems.append("open_with.\(key): can't find the app \"\(spec)\"")
                    }
                }
                let links = AppResolver.links(config.openLinks, among: apps)
                problems += links.problems
                let terminal = AppResolver.resolve(config.terminal, among: apps)
                if terminal == nil { problems.append("actions.terminal: can't find the app \"\(config.terminal)\"") }
                return (openWith, links.apps, terminal, problems)
            }
            guard generation == resolveGeneration else { return }
            launcher.openWithApps = openWith
            launcher.openLinks = openLinks
            launcher.terminalApp = terminal
            appProblems = problems
            publishProblems()
        }
    }

    private func run(_ command: Command) {
        switch command {
        case .clipboard: panel?.launcher.switchMode(to: .clipboard)
        case .pauseClipboard: setRecordingPaused(true)
        case .resumeClipboard: setRecordingPaused(false)
        case .clearClipboard: clearClipboard()
        case .installUpdate: updater.installNow()
        case .checkForUpdates: updater.checkNow()
        case .openConfig: configStore.open()
        case .reloadConfig: configStore.reload()
        case .quit: NSApp.terminate(nil)
        }
    }

    /// Rescans the app folders on a worker thread, then swaps the new index in on the main thread.
    private func rebuildIndex() {
        indexGeneration += 1
        let generation = indexGeneration
        Task {
            let index = await runInBackground(qos: .utility) {
                let launcher = Bundle.main.bundleURL.resolvingSymlinksInPath().path
                let apps = AppScanner.scan(AppScanner.defaultRoots, extras: AppScanner.defaultExtras)
                    .filter { $0.id != launcher }
                return SearchIndex(items: apps + Command.allCases.map(Item.init(command:)))
            }
            // A newer rescan started meanwhile: its result wins.
            guard generation == indexGeneration else { return }
            panel?.launcher.index = index
            resolveApps()
        }
    }
}
