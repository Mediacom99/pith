import Foundation
import LauncherCore
import TestSupport
import Testing

@testable import Launcher

/// Reading config.toml, on temporary files: never the real `~/.config/pith/`.
struct ConfigStoreTests {
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
