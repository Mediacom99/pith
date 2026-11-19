import AppKit
import Carbon.HIToolbox
import LauncherCore
import os

enum Log {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "launcher", category: "app")
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
        if !hotKeys.register(launcherShortcut, action: { panel.toggle() }) {
            Log.app.error("Couldn't register ⌘P: another app already holds it")
        }

        rebuildIndex()
        watcher = DirectoryWatcher(paths: AppScanner.defaultRoots.map(\.path), queue: .main) { [weak self] paths in
            guard paths.contains(where: AppScanner.affectsIndex) else { return }
            Task { @MainActor in self?.rebuildIndex() }
        }
    }

    /// Rescans the app folders off the main thread, then swaps the new index in.
    private func rebuildIndex() {
        indexGeneration += 1
        let generation = indexGeneration
        Task {
            let index = await Task.detached(priority: .utility) {
                AppIndex(apps: AppScanner.scan(AppScanner.defaultRoots))
            }.value
            // A newer rescan started meanwhile: its result wins.
            guard generation == indexGeneration else { return }
            panel?.launcher.index = index
        }
    }
}
