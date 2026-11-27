import AppKit
import Foundation
import LauncherCore
import TestSupport
import Testing

@testable import Launcher

struct AppResolverTests {
    private let terminal = URL(filePath: "/System/Applications/Utilities/Terminal.app")
    private var apps: [AppResolver.App] {
        AppScanner.scan(AppScanner.defaultRoots, extras: AppScanner.defaultExtras).compactMap { item in
            item.url.map { AppResolver.App(names: [item.name, $0.deletingPathExtension().lastPathComponent], url: $0) }
        }
    }

    @Test func findsAppsByNameBundleIDOrPath() {
        #expect(AppResolver.resolve("terminal", among: apps)?.path == terminal.path, "by name, any case")
        #expect(AppResolver.resolve("com.apple.Terminal", among: apps)?.lastPathComponent == "Terminal.app")
        #expect(AppResolver.resolve(terminal.path, among: apps) == terminal)
        #expect(AppResolver.resolve("No Such App", among: apps) == nil)
        #expect(AppResolver.resolve("/nonexistent/X.app", among: apps) == nil)
    }

    @Test func linksFindTheirAppsAndHttpsCoversHttp() {
        let (found, problems) = AppResolver.links(["https": "Terminal", "mailto": "No Such App"], among: apps)
        #expect(found.mapValues(\.path) == ["https": terminal.path, "http": terminal.path])
        #expect(problems == ["open_links.mailto: can't find the app \"No Such App\""])

        let own = AppResolver.links(["https": "Terminal", "http": "No Such App"], among: apps)
        #expect(
            own.apps.mapValues(\.path) == ["https": terminal.path],
            "http set on its own isn't replaced, even when it's not found")
    }

    /// Each `[open_with]` app is looked up once, and one that isn't found is one problem, whatever it was set for.
    @Test func openWithSaysOnceWhichAppIsMissing() {
        let (found, problems) = AppResolver.openWith(
            [
                "md": "Terminal", "txt": "No Such App", "json": "No Such App", "csv": "Other Missing",
                "com.acme.nothing": "Terminal",
            ], among: apps)
        #expect(found.mapValues(\.path) == ["md": terminal.path])
        #expect(
            problems == [
                "open_with \"com.acme.nothing\" isn't a known file type",
                "open_with.csv: can't find the app \"Other Missing\"",
                "open_with: can't find the app \"No Such App\", set for json, txt",
            ])
    }

    @Test func picksTheOpenWithAppByExtensionThenMostSpecificType() {
        let a = URL(filePath: "/A.app")
        let b = URL(filePath: "/B.app")
        let c = URL(filePath: "/C.app")
        let openWith = ["md": a, "public.image": b, "public.png": c]
        #expect(AppResolver.app(forFile: URL(filePath: "/x/notes.md"), openWith: openWith) == a)
        #expect(AppResolver.app(forFile: URL(filePath: "/x/shot.png"), openWith: openWith) == c)
        #expect(AppResolver.app(forFile: URL(filePath: "/x/photo.jpg"), openWith: openWith) == b)
        #expect(AppResolver.app(forFile: URL(filePath: "/x/plain.txt"), openWith: openWith) == nil)
    }

    @Test func listsAppsThatCanOpenAFile() {
        let choices = AppResolver.apps(
            toOpen: URL(filePath: "/System/Library/CoreServices/SystemVersion.plist"), among: apps)
        let allApps = choices.allSatisfy { $0.isApp }
        #expect(!choices.isEmpty)
        #expect(allApps)
    }
}

/// The icons of file types, rendered as they're asked for.
@MainActor
struct IconStoreTests {
    /// Past `typesKept` types, closing the panel drops the least recently asked for, so odd extensions don't pile up.
    @Test func typeIconsAreTrimmedToTheMostRecent() async {
        let icons = IconStore(typesKept: 8)
        let files = (0..<12).map { URL(filePath: "/Users/me/Documents/Acme/backup.2025-\($0)") }
        for file in files { _ = icons.icon(forFile: file) }
        #expect(await eventuallyTrue { icons.typeCount == 12 })
        _ = icons.icon(forFile: files[0])
        icons.trimTypes()
        #expect(icons.typeCount == 6, "down to three quarters of what's kept")
        #expect(icons.icon(forFile: files[0]) != nil, "asked for again last, so kept")
        #expect(icons.icon(forFile: files[1]) == nil, "among the least recent")
    }
    /// Icons drawn for a 1x screen are drawn again when a sharper one appears (the lid opened, a display plugged in),
    /// and not when the screens change without a sharper one.
    @Test func aSharperScreenRedrawsTheIcons() async throws {
        let icons = IconStore()
        let textEdit = URL(filePath: "/System/Applications/TextEdit.app")
        var scale: CGFloat = 1
        icons.screenScale = { scale }
        icons.load([textEdit])
        #expect(await eventuallyTrue { icons.icon(for: textEdit)?.width == Int(Layout.iconSize) })
        #expect(icons.drawnScale == 1)

        scale = 2
        icons.screensChanged()
        #expect(icons.drawnScale == 2, "drawing again for the sharper screen")
        #expect(await eventuallyTrue { icons.icon(for: textEdit)?.width == Int(Layout.iconSize * 2) })
    }

    /// Open With… lists apps outside the indexed folders: their icons are drawn too.
    @Test func appsAddedOutsideTheIndexGetIcons() async throws {
        let icons = IconStore()
        let archiveUtility = URL(filePath: "/System/Library/CoreServices/Applications/Archive Utility.app")
        try #require(FileManager.default.fileExists(atPath: archiveUtility.path))
        icons.load([])
        icons.add(apps: [archiveUtility])
        #expect(await eventuallyTrue { icons.icon(for: archiveUtility) != nil })
        icons.load([])
        #expect(icons.icon(for: archiveUtility) != nil, "kept as the index changes")
    }

    /// An app updated in place gets its new icon when the apps are read again; the others aren't drawn again.
    @Test func anUpdatedAppIsDrawnAgain() async throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("Acme.app/Contents/Info.plist")
        let acme = folder.url.appending(path: "Acme.app")
        let textEdit = URL(filePath: "/System/Applications/TextEdit.app")
        let icons = IconStore()
        icons.load([acme, textEdit])
        #expect(await eventuallyTrue { icons.appsRendered == 2 })

        icons.load([acme, textEdit], recheck: true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(icons.appsRendered == 2, "nothing changed")

        let info = acme.appending(path: "Contents/Info.plist").path
        try FileManager.default.setAttributes([.modificationDate: Date.now + 60], ofItemAtPath: info)
        icons.load([acme, textEdit], recheck: true)
        #expect(await eventuallyTrue { icons.appsRendered == 3 })
    }

    /// An app that isn't installed stays missing while another app is looked up: its rows don't blink.
    @Test func aMissingAppStaysMissingDuringOtherLookups() async {
        let icons = IconStore()
        _ = icons.icon(forBundleID: "example.acme.not-installed")
        #expect(await eventuallyTrue { icons.isMissing(bundleID: "example.acme.not-installed") })
        _ = icons.icon(forBundleID: "com.apple.TextEdit")
        #expect(icons.isMissing(bundleID: "example.acme.not-installed"))
        #expect(!icons.isMissing(bundleID: "com.apple.TextEdit"), "not until it's looked up")
    }
}
