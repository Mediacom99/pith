import Foundation
import LauncherCore
import TestSupport
import Testing

struct AppScannerTests {
    @Test func includesExtrasLikeFinder() {
        let apps = AppScanner.scan([], extras: AppScanner.defaultExtras + [URL(filePath: "/nonexistent.app")])
        #expect(apps.map(\.name) == ["Finder"])
    }

    @Test func idsAreResolvedPaths() throws {
        let root = try TemporaryDirectory()
        try root.makeFolder("Real/Tool.app")
        let apps = AppScanner.scan([root.url])
        #expect(apps.first?.id == root.url.appending(path: "Real/Tool.app").resolvingSymlinksInPath().path)
    }

    @Test func findsTheSystemApps() {
        let apps = AppScanner.scan([URL(filePath: "/System/Applications")])
        let files = Set(apps.compactMap(\.url?.lastPathComponent))
        #expect(files.contains("Calculator.app"))
        #expect(files.contains("Terminal.app"), "subfolders such as Utilities are scanned")
        #expect(!apps.contains { $0.id.contains(".app/") }, "never looks inside a bundle")
        #expect(apps.allSatisfy { !$0.name.isEmpty && !$0.name.hasSuffix(".app") })
    }

    @Test func skipsBundleContentsHiddenFilesAndDeepFolders() throws {
        let root = try TemporaryDirectory()
        try root.makeFolder("Top.app/Contents/Nested.app")
        try root.makeFolder("One/Two/Three.app")
        try root.makeFolder("One/Two/Three/Four.app")
        try root.makeFolder(".Hidden.app")

        let apps = AppScanner.scan([root.url], maxDepth: 3)
        #expect(Set(apps.compactMap(\.url?.lastPathComponent)) == ["Top.app", "Three.app"])
        #expect(Set(apps.map(\.name)) == ["Top", "Three"])
    }

    @Test func countsAnAppReachedThroughASymlinkOnce() throws {
        let root = try TemporaryDirectory()
        try root.makeFolder("Real/Tool.app")
        try FileManager.default.createSymbolicLink(
            at: root.url.appending(path: "Tool.app"),
            withDestinationURL: root.url.appending(path: "Real/Tool.app")
        )
        #expect(AppScanner.scan([root.url]).count == 1)
    }

    @Test func findsAppsWithTheHiddenFlag() throws {
        // Like /Applications/Safari.app, which Finder shows although it's flagged hidden.
        let root = try TemporaryDirectory()
        try root.makeFolder("Flagged.app")
        var flagged = root.url.appending(path: "Flagged.app")
        var values = URLResourceValues()
        values.isHidden = true
        try flagged.setResourceValues(values)
        #expect(AppScanner.scan([root.url]).map(\.name) == ["Flagged"])
    }

    @Test func findsSafari() {
        #expect(AppScanner.scan([URL(filePath: "/Applications")]).contains { $0.name == "Safari" })
    }

    @Test func missingFoldersAreSkipped() {
        #expect(AppScanner.scan([URL(filePath: "/nonexistent-\(UUID().uuidString)")]).isEmpty)
    }

    @Test func changesInsideBundlesDontTriggerARescan() {
        #expect(AppScanner.affectsIndex("/Applications/"))
        #expect(AppScanner.affectsIndex("/Applications/Utilities/"))
        #expect(!AppScanner.affectsIndex("/Applications/Safari.app/Contents/"))
    }
}
