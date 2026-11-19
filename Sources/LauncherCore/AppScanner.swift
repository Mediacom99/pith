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

    /// Every `.app` under `roots`, at most `maxDepth` folders down, never looking inside a bundle.
    /// Missing roots and unreadable folders are skipped.
    public static func scan(_ roots: [URL], maxDepth: Int = 3) -> [AppItem] {
        var seen = Set<String>()
        var apps: [AppItem] = []
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
                    // The same bundle can be reachable twice through a symlink.
                    guard seen.insert(url.resolvingSymlinksInPath().path).inserted else { continue }
                    apps.append(AppItem(name: displayName(of: url), url: url))
                } else if walker.level >= maxDepth {
                    walker.skipDescendants()
                }
            }
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
