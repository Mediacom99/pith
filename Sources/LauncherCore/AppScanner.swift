import Foundation

/// Finds application bundles on disk.
public enum AppScanner {
    /// The folders FEATURES.md §4.1 names. Their subfolders, such as Utilities, are scanned too.
    public static var defaultRoots: [URL] {
        [
            URL(filePath: "/Applications"),
            URL(filePath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
        ]
    }

    /// Apps outside those folders that belong in the index anyway.
    public static let defaultExtras = [URL(filePath: "/System/Library/CoreServices/Finder.app")]

    /// Every `.app` under `roots`, at most `maxDepth` folders down and never inside a bundle, plus the `extras` that
    /// exist. Missing roots and unreadable folders are skipped. Each item's id is its bundle path with symlinks
    /// resolved, so an app reachable twice is listed once.
    public static func scan(_ roots: [URL], extras: [URL] = [], maxDepth: Int = 3) -> [Item] {
        var seen = Set<String>()
        var apps: [Item] = []
        func add(_ url: URL) {
            let id = url.resolvingSymlinksInPath().path
            guard seen.insert(id).inserted else { return }
            apps.append(Item(name: displayName(of: url), appAt: url, id: id))
        }

        for root in roots {
            guard
                let walker = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.localizedNameKey],
                    // Not .skipsHiddenFiles: /Applications/Safari.app is a symlink with the "hidden" flag set.
                    options: [.skipsPackageDescendants]
                )
            else { continue }
            for case let url as URL in walker {
                if url.lastPathComponent.hasPrefix(".") {
                    walker.skipDescendants()
                } else if url.pathExtension == "app" {
                    add(url)
                } else if walker.level >= maxDepth {
                    walker.skipDescendants()
                }
            }
        }
        for url in extras where FileManager.default.fileExists(atPath: url.path) {
            add(url)
        }
        return apps
    }

    /// Whether an FSEvents change at `path` can add or remove an app. Changes inside a bundle (updates, caches)
    /// can't, so they don't trigger a rescan.
    public static func affectsIndex(_ path: String) -> Bool {
        !path.contains(".app/")
    }

    private static func displayName(of url: URL) -> String {
        let name = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? url.lastPathComponent
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
