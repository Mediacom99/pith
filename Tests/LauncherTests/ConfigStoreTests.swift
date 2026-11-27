import Foundation
import LauncherCore
import TestSupport
import Testing

@testable import Launcher

/// Reading config.toml, on temporary files: never the real `~/.config/pith/`.
struct ConfigStoreTests {
    /// Open Config opens config.toml in the app `[open_with]` gives `toml` (decision 82).
    @Test func openConfigFollowsOpenWith() {
        let editor = URL(filePath: "/Applications/Acme Editor.app")
        #expect(ConfigStore.editor(for: ConfigStore.file, openWith: ["toml": editor]) == editor)
        #expect(ConfigStore.editor(for: ConfigStore.file, openWith: ["md": editor]) != editor)
    }

    /// A file that's gone or isn't text changes nothing, as a file that isn't valid TOML doesn't (decision 59).
    @Test func aFileThatCantBeReadChangesNothing() throws {
        let folder = try TemporaryDirectory()
        let file = folder.url.appending(path: "config.toml")
        var current = Config()
        current.clipboardMaxAgeDays = 365

        let (missing, missingProblems) = ConfigStore.read(file, previous: current)
        #expect(missing == current)
        #expect(missingProblems == ["config.toml is missing, so the settings stay as they were"])

        try Data([0xFF, 0xFE, 0xFD]).write(to: file)
        let (binary, binaryProblems) = ConfigStore.read(file, previous: current)
        #expect(binary == current)
        #expect(binaryProblems == ["config.toml isn't UTF-8 text, so the settings stay as they were"])

        try Data("[clipboard]\nmax_age_days = 90".utf8).write(to: file)
        #expect(ConfigStore.read(file, previous: current).0.clipboardMaxAgeDays == 90)
    }

    /// A config.toml that's a symlink (a dotfiles manager's) reloads when its target is saved; a swap file beside it
    /// doesn't reload anything.
    @MainActor
    @Test func aSymlinkedConfigReloadsAndASwapFileDoesnt() async throws {
        let folder = try TemporaryDirectory()
        try folder.makeFolder("dotfiles")
        try folder.makeFolder("config/pith")
        let target = folder.url.appending(path: "dotfiles/pith.toml")
        try Data("[clipboard]\nmax_age_days = 60".utf8).write(to: target)
        let file = folder.url.appending(path: "config/pith/config.toml")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)

        let store = ConfigStore(file: file)
        var loads = 0
        store.onChange = { _ in loads += 1 }
        await store.start()
        #expect(store.config.clipboardMaxAgeDays == 60 && loads == 1)

        try Data("swap".utf8).write(to: folder.url.appending(path: "config/pith/.config.toml.swp"))
        try await Task.sleep(for: .seconds(1))
        #expect(loads == 1, "an editor's swap file isn't the config")

        try Data("[clipboard]\nmax_age_days = 90".utf8).write(to: target, options: .atomic)
        #expect(await eventuallyTrue { store.config.clipboardMaxAgeDays == 90 })
    }
}

/// The history at launch, on temporary files: never the real `~/Library/Application Support/pith/`.
struct HistoryStoreTests {
    /// What was deleted is forgotten; what's on a drive that isn't plugged in, or can't be read, is kept.
    @MainActor
    @Test func onlyWhatsReallyGoneIsForgotten() async throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("Acme/notes.md")
        try folder.makeFolder("Locked")
        try folder.makeFile("Locked/plan.md")
        let locked = folder.url.path + "/Locked"
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked) }
        let kept = [
            "file:" + folder.url.path + "/Acme/notes.md", "file:/Volumes/Acme Backup \(UUID().uuidString)/report.pdf",
            "file:" + locked + "/plan.md",
        ]
        let deleted = "file:" + folder.url.path + "/Acme/old.md"
        var history = History()
        for id in kept + [deleted] { history.record(id) }
        let file = folder.url.appending(path: "history.json")
        try JSONEncoder().encode(history).write(to: file)

        let store = HistoryStore(file: file)
        await store.load()
        #expect(await eventuallyTrue { Set(store.history.ids) == Set(kept) }, "checked after the load, on a worker")
    }
}
