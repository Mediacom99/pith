import AppKit
import LauncherCore

/// `~/.config/pith/config.toml` (FEATURES.md §8): created with commented defaults when missing, read and parsed
/// on a worker, and reloaded whenever it changes. A config.toml that's a symlink (a dotfiles manager's) reloads when
/// its target changes; an editor's swap file beside it doesn't reload anything.
final class ConfigStore {
    nonisolated static let file = URL.homeDirectory.appending(path: ".config/pith/config.toml")

    /// `ConfigStore.file`, or a temporary one in tests.
    let file: URL
    private(set) var config = Config()
    /// What's wrong in the file, with line numbers. Wrong settings stay as they were (decision 59).
    private(set) var problems: [String] = []
    private var watcher: DirectoryWatcher?
    private var generation = 0
    /// Whether `config` came from the file yet: until then, a mistake falls back to the defaults.
    private var hasLoaded = false
    /// The folders watched, and the names in them that are the file: its own, and its target's if it's a symlink.
    private var watched: (folders: [String], names: Set<String>)?

    init(file: URL = ConfigStore.file) {
        self.file = file
    }

    /// Called after every load, with the settings before it.
    var onChange: ((_ previous: Config) -> Void)?

    /// Loads the settings, creating the file first if needed, then watches it.
    func start() async {
        let file = self.file
        await runInBackground(qos: .userInitiated) { Self.createIfMissing(file) }
        await load()
    }

    /// Watches the file's folder, and its target's if it's a symlink, for changes to the file itself; again when the
    /// symlink points somewhere else.
    private func watch(_ watched: (folders: [String], names: Set<String>)) {
        guard self.watched?.folders != watched.folders || self.watched?.names != watched.names else { return }
        self.watched = watched
        let names = watched.names
        watcher = DirectoryWatcher(paths: watched.folders, fileEvents: true, latency: 0.2, queue: .main) {
            [weak self] events in
            guard events.contains(where: { names.contains(($0.path as NSString).lastPathComponent) }) else { return }
            Task { @MainActor in await self?.load() }
        }
    }

    func reload() {
        Task { await load() }
    }

    /// Opens the file in the app `[open_with]` sets for it (`toml`, decision 82), else the default editor for .toml
    /// files, else TextEdit.
    func open(openWith: [String: URL]) {
        let file = self.file
        Task {
            let editor = await runInBackground(qos: .userInitiated) {
                Self.createIfMissing(file)
                return Self.editor(for: file, openWith: openWith)
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
        let file = self.file
        let current = hasLoaded ? config : nil
        let (config, problems, watched) = await runInBackground(qos: .userInitiated) {
            let (config, problems) = Self.read(file, previous: current)
            return (config, problems, Self.watched(file))
        }
        // A newer load started meanwhile: its result wins.
        guard generation == self.generation else { return }
        watch(watched)
        let previous = self.config
        self.config = config
        self.problems = problems
        hasLoaded = true
        for problem in problems { Log.app.error("config.toml \(problem, privacy: .public)") }
        onChange?(previous)
    }

    /// The folders to watch for `file`, as FSEvents reports them (symlinks resolved), and the names that are it.
    nonisolated static func watched(_ file: URL) -> (folders: [String], names: Set<String>) {
        let target = file.resolvingSymlinksInPath()
        let folders = [file.deletingLastPathComponent(), target.deletingLastPathComponent()].map {
            $0.resolvingSymlinksInPath().path
        }
        return (Array(Set(folders)).sorted(), [file.lastPathComponent, target.lastPathComponent])
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

    /// The app Open Config opens `file` in: `[open_with]`'s for it, else the default app for it, else TextEdit. Asks
    /// LaunchServices, so call it on a worker.
    nonisolated static func editor(for file: URL, openWith: [String: URL]) -> URL {
        AppResolver.app(forFile: file, openWith: openWith) ?? NSWorkspace.shared.urlForApplication(toOpen: file)
            ?? URL(filePath: "/System/Applications/TextEdit.app")
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
