import Foundation
import LauncherCore
import Testing

struct DirectoryWatcherTests {
    @Test func reportsAChange() async throws {
        let folder = try TemporaryDirectory()
        let (changes, continuation) = AsyncStream.makeStream(of: [String].self)
        let watcher = try #require(
            DirectoryWatcher(paths: [folder.url.path], latency: 0.05, queue: .global()) { continuation.yield($0) }
        )

        try Data("hello".utf8).write(to: folder.url.appending(path: "new.txt"))

        let changed = try #require(await first(of: changes, within: .seconds(10)))
        // FSEvents reports canonical paths (/private/var/…), so match on the folder's unique name.
        #expect(changed.contains { $0.contains(folder.url.lastPathComponent) })
        withExtendedLifetime(watcher) {}
    }
}

private func first<Element: Sendable>(of stream: AsyncStream<Element>, within timeout: Duration) async -> Element? {
    await withTaskGroup(of: Element?.self) { group in
        group.addTask { await stream.first { _ in true } }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        defer { group.cancelAll() }
        return await group.next() ?? nil
    }
}
