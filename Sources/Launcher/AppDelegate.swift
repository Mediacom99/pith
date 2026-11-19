import AppKit
import Carbon.HIToolbox
import LauncherCore
import os

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "launcher"
    static let app = Logger(subsystem: subsystem, category: "app")
    /// Latencies, at debug level: next to free unless someone is streaming them (`make logs`).
    static let perf = Logger(subsystem: subsystem, category: "perf")

    /// Logs the time since `start`, in seconds since boot like event timestamps.
    static func latency(_ label: String, since start: TimeInterval) {
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        perf.debug("\(label, privacy: .public): \(milliseconds, format: .fixed(precision: 2)) ms")
    }
}

/// Wires the pieces together: builds the panel up front, registers ⌘P, keeps the app index fresh.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: LauncherPanel?
    private let hotKeys = HotKeyCenter()
    private var watcher: DirectoryWatcher?
    private var indexGeneration = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Built now, so ⌘P only has to show it.
        let panel = LauncherPanel()
        self.panel = panel

        let launcherShortcut = HotKeyCenter.Shortcut(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey))
        if !hotKeys.register(launcherShortcut, action: { panel.toggle(pressedAt: $0) }) {
            Log.app.error("Couldn't register ⌘P: another app already holds it")
        }

        rebuildIndex()
        watcher = DirectoryWatcher(paths: AppScanner.defaultRoots.map(\.path), queue: .main) { [weak self] paths in
            guard paths.contains(where: AppScanner.affectsIndex) else { return }
            Task { @MainActor in self?.rebuildIndex() }
        }
    }

    /// Rescans the app folders on a worker thread, then swaps the new index in on the main thread.
    private func rebuildIndex() {
        indexGeneration += 1
        let generation = indexGeneration
        Task {
            let index = await runInBackground(qos: .utility) {
                AppIndex(apps: AppScanner.scan(AppScanner.defaultRoots))
            }
            // A newer rescan started meanwhile: its result wins.
            guard generation == indexGeneration else { return }
            panel?.launcher.index = index
        }
    }
}
