import AppKit

/// The open apps (those with a Dock icon), most recently used first like ⌘Tab (decision 13), identified by resolved
/// bundle path, the same id the index uses.
///
/// `NSWorkspace.runningApplications` is the source of truth: every launch or quit re-reads it, and so does every show,
/// in case a notification was missed. Notifications only say when to look, and activations set the order.
final class RunningApps {
    /// Ids, most recently active first.
    private(set) var order: [String] = []
    private var apps: [String: NSRunningApplication] = [:]
    /// Each process's id, resolved once, so an app switch never touches the file system.
    private var ids: [pid_t: String] = [:]
    private var observers: [any NSObjectProtocol] = []

    /// Called after every change. `membership` is true when an app launched or quit, false for a switch.
    var onChange: ((_ membership: Bool) -> Void)?

    init() {
        let workspace = NSWorkspace.shared
        sync()
        if let front = workspace.frontmostApplication { activated(front) }

        let names = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        observers = names.map { name in
            workspace.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                // Posted on the main queue, as asked.
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWorkspace.didActivateApplicationNotification, let app {
                        self.activated(app)
                    } else if self.sync() {
                        self.onChange?(true)
                    }
                }
            }
        }
    }

    func isRunning(_ id: String) -> Bool {
        apps[id] != nil
    }

    func application(_ id: String) -> NSRunningApplication? {
        apps[id]
    }

    /// Re-reads the open apps, keeping the most-recently-used order of those still open; new ones go last, newest
    /// launch first. True if anything changed.
    @discardableResult
    func sync() -> Bool {
        var current: [String: NSRunningApplication] = [:]
        let open = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .sorted { ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast) }
        var launched: [String] = []
        for app in open {
            guard let id = id(of: app) else { continue }
            if current[id] == nil { launched.append(id) }
            current[id] = app
        }
        let alive = Set(open.map(\.processIdentifier))
        ids = ids.filter { alive.contains($0.key) }

        let kept = order.filter { current[$0] != nil }
        let new = kept + launched.filter { !kept.contains($0) }
        let changed = new != order || Set(current.keys) != Set(apps.keys)
        order = new
        apps = current
        return changed
    }

    private func id(of app: NSRunningApplication) -> String? {
        if let id = ids[app.processIdentifier] { return id }
        guard let url = app.bundleURL else { return nil }
        let id = url.resolvingSymlinksInPath().path
        ids[app.processIdentifier] = id
        return id
    }

    private func activated(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, let id = id(of: app) else { return }
        let membership = apps[id] == nil && sync()
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        onChange?(membership)
    }
}
