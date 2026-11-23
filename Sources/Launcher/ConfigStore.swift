import AppKit
import LauncherCore

/// `~/.config/pith/config.toml` (FEATURES.md §8): created with commented defaults when missing, read and parsed
/// on a worker, and reloaded whenever something in its folder changes.
final class ConfigStore {
    nonisolated static let file = URL.homeDirectory.appending(path: ".config/pith/config.toml")

    private(set) var config = Config()
    /// What's wrong in the file, with line numbers. Wrong settings stay as they were (decision 59).
    private(set) var problems: [String] = []
    private var watcher: DirectoryWatcher?
    private var generation = 0
    /// Whether `config` came from the file yet: until then, a mistake falls back to the defaults.
    private var hasLoaded = false

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
        let current = hasLoaded ? config : nil
        let (config, problems) = await runInBackground(qos: .userInitiated) { Self.read(file, previous: current) }
        // A newer load started meanwhile: its result wins.
        guard generation == self.generation else { return }
        let previous = self.config
        self.config = config
        self.problems = problems
        hasLoaded = true
        for problem in problems { Log.app.error("config.toml \(problem, privacy: .public)") }
        onChange?(previous)
    }

    /// The settings in `file`, given the ones Pith has now (`previous`, nil at launch). A file that's gone, can't be
    /// read or isn't text changes nothing, as a file that isn't valid TOML doesn't (decision 59).
    nonisolated static func read(_ file: URL, previous: Config?) -> (Config, [String]) {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            return Config.unchanged("config.toml is missing", previous: previous)
        } catch {
            return Config.unchanged("config.toml can't be read", previous: previous)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return Config.unchanged("config.toml isn't UTF-8 text", previous: previous)
        }
        return Config.parse(text, previous: previous)
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
