import Foundation
import LauncherCore
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
}
