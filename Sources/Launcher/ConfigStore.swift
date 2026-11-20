import AppKit
import LauncherCore

/// `~/.config/pith/config.toml` (FEATURES.md §8): created with commented defaults when missing, read and parsed
/// on a worker, and reloaded whenever something in its folder changes.
final class ConfigStore {
    nonisolated static let file = URL.homeDirectory.appending(path: ".config/pith/config.toml")

    private(set) var config = Config()
    /// What's wrong in the file, with line numbers. Wrong settings keep their defaults.
    private(set) var problems: [String] = []
    private var watcher: DirectoryWatcher?
    private var generation = 0

    /// Called after every load, with the settings before it.
    var onChange: ((_ previous: Config) -> Void)?

    /// Loads the settings, creating the file first if needed, then watches it.
    func start() async {
        let file = Self.file
        await runInBackground(qos: .userInitiated) { Self.createIfMissing(file) }
        watcher = DirectoryWatcher(paths: [file.deletingLastPathComponent().path], latency: 0.2, queue: .main) {
            [weak self] _ in
            Task { @MainActor in await self?.load() }
        }
        await load()
    }

    func reload() {
        Task { await load() }
    }

    /// Opens the file in the default editor for .toml files, or TextEdit when there's none.
    func open() {
        let file = Self.file
        Task {
            let editor = await runInBackground(qos: .userInitiated) {
                Self.createIfMissing(file)
                return NSWorkspace.shared.urlForApplication(toOpen: file)
                    ?? URL(filePath: "/System/Applications/TextEdit.app")
            }
            do {
                _ = try await NSWorkspace.shared.open([file], withApplicationAt: editor, configuration: .init())
            } catch {
                Log.app.error("Couldn't open config.toml: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func load() async {
        generation += 1
        let generation = generation
        let file = Self.file
        let (config, problems) = await runInBackground(qos: .userInitiated) { Self.read(file) }
        // A newer load started meanwhile: its result wins.
        guard generation == self.generation else { return }
        let previous = self.config
        self.config = config
        self.problems = problems
        for problem in problems { Log.app.error("config.toml \(problem, privacy: .public)") }
        onChange?(previous)
    }

    private nonisolated static func read(_ file: URL) -> (Config, [String]) {
        guard let data = try? Data(contentsOf: file) else { return (Config(), []) }
        guard let text = String(data: data, encoding: .utf8) else {
            return (Config(), ["config.toml isn't UTF-8 text"])
        }
        return Config.parse(text)
    }

    private nonisolated static func createIfMissing(_ file: URL) {
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Config.template.utf8).write(to: file, options: .withoutOverwriting)
        } catch {
            Log.app.error("Couldn't create config.toml: \(error.localizedDescription, privacy: .public)")
        }
    }
}
