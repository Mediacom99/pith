import AppKit

/// The app each link scheme opens in, for "Open in Safari" and Open Link: `[open_links]`'s (decision 16), else the
/// scheme's default app, looked up on a worker the first time a scheme is asked for.
final class LinkApps {
    typealias App = (url: URL?, name: String?)

    /// `[open_links]`, resolved: URL scheme → app. A change forgets what was looked up.
    var configured: [String: URL] = [:] {
        didSet { if configured != oldValue { known = [:] } }
    }
    /// Called on the main thread when a lookup lands.
    var onChange: (() -> Void)?

    /// By scheme; `(nil, nil)` while it's looked up, or when no app opens it.
    private var known: [String: App] = [:]

    /// The app that opens `link`, or nil when it isn't a URL or the first lookup for its scheme is under way.
    func app(for link: String) -> App? {
        guard let url = URL(string: link), let scheme = url.scheme?.lowercased() else { return nil }
        if let app = known[scheme] { return app }
        known[scheme] = (nil, nil)
        let configured = configured[scheme]
        Task {
            let app = await runInBackground(qos: .userInitiated) { () -> App in
                guard let app = configured ?? NSWorkspace.shared.urlForApplication(toOpen: url) else {
                    return (nil, nil)
                }
                let name = FileManager.default.displayName(atPath: app.path)
                return (app, name.hasSuffix(".app") ? String(name.dropLast(4)) : name)
            }
            known[scheme] = app
            onChange?()
        }
        return nil
    }
}
