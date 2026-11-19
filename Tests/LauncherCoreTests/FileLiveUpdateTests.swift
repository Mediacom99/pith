import Foundation
import LauncherCore
import Synchronization
import TestSupport
import Testing

/// Polls `condition` until it holds or `timeout` passes. FSEvents delivers within its latency (0.5 s) plus a little.
private func eventually(within timeout: Duration = .seconds(10), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}

private final class Removals: Sendable {
    let paths = Mutex<[String]>([])
}

private func paths(_ engine: FileSearchEngine, _ query: String) async -> [String] {
    await engine.search(query, limit: 50, generation: Int.random(in: 1...Int.max))?.map(\.path) ?? []
}

@Suite(.serialized) struct FileLiveUpdateTests {
    private func engine(at root: String, removals: Removals = Removals(), maxDepth: Int = 6) async -> FileSearchEngine {
        let engine = FileSearchEngine { paths in removals.paths.withLock { $0 += paths } }
        await engine.rebuild(FileRules(roots: [root], ignore: IgnoreRules([".*", "node_modules"]), maxDepth: maxDepth))
        return engine
    }

    @Test func picksUpNewFilesAndFoldersMovedIn() async throws {
        let folder = try TemporaryDirectory()
        let outside = try TemporaryDirectory()
        let root = folder.canonicalPath
        let engine = await engine(at: root)

        try folder.makeFile("fresh-report.txt")
        #expect(await eventually { await paths(engine, "fresh-report") == [root + "/fresh-report.txt"] })

        try outside.makeFile("Bundle/inner-notes.md")
        try FileManager.default.moveItem(
            at: outside.url.appending(path: "Bundle"), to: folder.url.appending(path: "Bundle"))
        #expect(await eventually { await paths(engine, "inner-notes") == [root + "/Bundle/inner-notes.md"] })
    }

    @Test func dropsDeletedAndRenamedItemsAndReportsThem() async throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("Old/stale-doc.txt")
        try folder.makeFile("draft-one.txt")
        let root = folder.canonicalPath
        let removals = Removals()
        let engine = await engine(at: root, removals: removals)
        #expect(await paths(engine, "stale-doc") == [root + "/Old/stale-doc.txt"])

        try FileManager.default.removeItem(at: folder.url.appending(path: "Old"))
        #expect(await eventually { await paths(engine, "stale-doc").isEmpty })
        #expect(removals.paths.withLock { $0.contains(root + "/Old") })

        try FileManager.default.moveItem(
            at: folder.url.appending(path: "draft-one.txt"), to: folder.url.appending(path: "draft-two.txt"))
        #expect(await eventually { await paths(engine, "draft") == [root + "/draft-two.txt"] })
    }

    @Test func leavesIgnoredAndTooDeepItemsOut() async throws {
        let folder = try TemporaryDirectory()
        let root = folder.canonicalPath
        let engine = await engine(at: root, maxDepth: 2)

        try folder.makeFile(".secret-zebra.txt")
        try folder.makeFile("node_modules/zebra-lib.js")
        try folder.makeFile("a/b/zebra-deep.txt")
        try folder.makeFile("zebra-marker.txt")
        // The marker shows the batch was applied; the others must not be there.
        #expect(await eventually { await paths(engine, "zebra-marker") == [root + "/zebra-marker.txt"] })
        #expect(await paths(engine, "zebra") == [root + "/zebra-marker.txt"])
        #expect(await paths(engine, "b").contains(root + "/a/b"))
    }
}
