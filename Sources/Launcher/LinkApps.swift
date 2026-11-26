import AppKit

/// The app each link scheme opens in, for "Open in Safari" and Open Link: `[open_links]`'s (decision 16), else the
/// scheme's default app. Looked up on a worker the first time a scheme is asked for, and again after the clipboard
/// opens, since the default browser can change while Pith runs.
final class LinkApps {
    typealias App = (url: URL?, name: String?)

    /// `[open_links]`, resolved: URL scheme → app. A change forgets what was looked up.
    var configured: [String: URL] = [:] {
        didSet {
            guard configured != oldValue else { return }
            known = [:]
            fresh = []
        }
    }
    /// Called on the main thread when a lookup lands with a different app.
    var onChange: (() -> Void)?

    /// By scheme; `(nil, nil)` when no app opens it.
    private var known: [String: App] = [:]
    /// Looked up since the clipboard last opened.
    private var fresh: Set<String> = []
    private var loading: Set<String> = []

    /// The clipboard opened: each scheme is looked up again the next time it's asked for.
    func markStale() {
        fresh = []
    }

    /// The app that opens `link`: the last one looked up, or while the first lookup runs the configured app without
    /// its name. Nil when it isn't a URL, or for a scheme `[open_links]` doesn't set until its lookup lands.
    func app(for link: String) -> App? {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased() else { return nil }
        let configured = configured[scheme]
        if !fresh.contains(scheme), loading.insert(scheme).inserted {
            Task {
                let app = await runInBackground(qos: .userInitiated) { () -> App in
                    guard let app = configured ?? NSWorkspace.shared.urlForApplication(toOpen: url) else {
                        return (nil, nil)
                    }
                    let name = FileManager.default.displayName(atPath: app.path)
                    return (app, name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
                }
                loading.remove(scheme)
                // A setting changed meanwhile: this answer is for the old one.
                guard configured == self.configured[scheme] else { return }
                fresh.insert(scheme)
                let changed = known[scheme].map { $0.url != app.url || $0.name != app.name } ?? true
                known[scheme] = app
                if changed { onChange?() }
            }
        }
        return known[scheme] ?? configured.map { (url: $0, name: nil) }
    }
}
