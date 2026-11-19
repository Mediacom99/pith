import AppKit
import LauncherCore
import os

nonisolated enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "launcher"
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
    private let hotKeys = HotKeyCenter()
    private lazy var files = FileSearchEngine { [weak self] removed in
        Task { @MainActor in self?.history.forget(paths: removed) }
    }
    private var fileRules: FileRules?
    private var panel: LauncherPanel?
    private var launcherHotkey: (hotkey: Hotkey, id: HotKeyCenter.ID)?
    private var appsWatcher: DirectoryWatcher?
    private var indexGeneration = 0
    private var hasAppliedConfig = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Built now, so the hotkey only has to show it.
        let launcher = LauncherViewController(history: history, running: RunningApps(), files: files)
        launcher.runCommand = { [weak self] in self?.run($0) }
        panel = LauncherPanel(launcher: launcher)

        configStore.onChange = { [weak self] previous in self?.apply(previous: previous) }
        Task {
            // The history is in before the config registers the hotkey, so nothing is opened before it loads.
            await history.load()
            await configStore.start()
        }

        rebuildIndex()
        appsWatcher = DirectoryWatcher(paths: AppScanner.defaultRoots.map(\.path), queue: .main) { [weak self] paths in
            guard paths.contains(where: AppScanner.affectsIndex) else { return }
            Task { @MainActor in self?.rebuildIndex() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        history.flush()
    }

    private func apply(previous: Config) {
        guard let panel else { return }
        let config = configStore.config
        var problems = configStore.problems

        if launcherHotkey?.hotkey != config.launcherHotkey {
            if let id = hotKeys.register(
                config.launcherHotkey, action: { [weak panel] in panel?.toggle(pressedAt: $0) })
            {
                if let old = launcherHotkey { hotKeys.unregister(old.id) }
                launcherHotkey = (config.launcherHotkey, id)
            } else {
                let fallback = launcherHotkey.map { ", still using \($0.hotkey)" } ?? ""
                problems.append("hotkeys.launcher \(config.launcherHotkey) is taken by another app\(fallback)")
            }
        }
        panel.launcher.emptyState = config.emptyState
        panel.launcher.problems = problems

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

    private func run(_ command: Command) {
        switch command {
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
        }
    }
}
