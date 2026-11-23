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
}
