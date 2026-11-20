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
