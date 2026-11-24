import AppKit
import LauncherCore
import UniformTypeIdentifiers

/// Turns the apps named in config.toml into app bundles, and picks the app `[open_with]` sets for a file. Asks
/// LaunchServices, so call it on a worker.
nonisolated enum AppResolver {
    /// An installed app, as the index knows it: its names (as listed, and its file name) and bundle.
    struct App: Sendable {
        let names: [String]
        let url: URL
    }

    /// An app given by name (as the launcher lists it, any case), bundle id (`com.microsoft.VSCode`) or path.
    static func resolve(_ spec: String, among apps: [App]) -> URL? {
        if spec.hasPrefix("/") || spec.hasPrefix("~") {
            let path = (spec as NSString).expandingTildeInPath
            return path.hasSuffix(".app") && FileManager.default.fileExists(atPath: path) ? URL(filePath: path) : nil
        }
        if let app = apps.first(where: { $0.names.contains { $0.caseInsensitiveCompare(spec) == .orderedSame } }) {
            return app.url
        }
        return spec.contains(".") && !spec.contains(" ")
            ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: spec) : nil
    }

    /// `[open_links]`'s apps by URL scheme, and a problem for each one that isn't found. `https` covers `http` too,
    /// unless `http` has its own.
    static func links(_ openLinks: [String: String], among apps: [App]) -> (apps: [String: URL], problems: [String]) {
        var found: [String: URL] = [:]
        var problems: [String] = []
        for (scheme, spec) in openLinks.sorted(by: { $0.key < $1.key }) {
            if let app = resolve(spec, among: apps) {
                found[scheme] = app
            } else {
                problems.append("open_links.\(scheme): can't find the app \"\(spec)\"")
            }
        }
        if openLinks["http"] == nil, let https = found["https"] { found["http"] = https }
        return (found, problems)
    }

    /// The app `[open_with]` sets for `file`: by its extension, else by the most specific type it conforms to.
    static func app(forFile file: URL, openWith: [String: URL]) -> URL? {
        let fileExtension = file.pathExtension.lowercased()
        if let app = openWith[fileExtension] { return app }
        guard let type = UTType(filenameExtension: fileExtension) else { return nil }
        let matches = openWith.compactMap { key, app -> (type: UTType, app: URL)? in
            guard key.contains("."), let declared = UTType(key), type.conforms(to: declared) else { return nil }
            return (declared, app)
        }
        // The most specific: one that conforms to all the others (public.png before public.image).
        let specific = matches.first { candidate in matches.allSatisfy { candidate.type.conforms(to: $0.type) } }
        return specific?.app ?? matches.first?.app
    }

    /// The apps that can open `file`, best first, as items to list.
    static func apps(toOpen file: URL, among apps: [App]) -> [Item] {
        NSWorkspace.shared.urlsForApplications(toOpen: file).map { url in
            let known = apps.first { $0.url.standardizedFileURL == url.standardizedFileURL }?.names.first
            let name = known ?? url.deletingPathExtension().lastPathComponent
            return Item(name: name, appAt: url)
        }
    }
}
