import AppKit

/// The open apps (those with a Dock icon), most recently used first like ⌘Tab (decision 13). Kept current by
/// NSWorkspace notifications, and identified by resolved bundle path, the same id the index uses.
final class RunningApps {
    /// Ids, most recently active first.
    private(set) var order: [String] = []
    private var apps: [String: NSRunningApplication] = [:]
    /// Each process's id, resolved once at launch, so an app switch never touches the file system.
    private var ids: [pid_t: String] = [:]
    private var observers: [any NSObjectProtocol] = []

    /// Called after every change. `membership` is true when an app launched or quit, false for a switch.
    var onChange: ((_ membership: Bool) -> Void)?

    init() {
        let workspace = NSWorkspace.shared
        let launched = workspace.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.launchDate ?? .distantPast) > ($1.launchDate ?? .distantPast) }
        for app in launched { track(app) }
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
                    guard let app else { return }
                    self?.handle(name, app)
                }
            }
        }
    }

    private func handle(_ name: Notification.Name, _ app: NSRunningApplication) {
        switch name {
        case NSWorkspace.didLaunchApplicationNotification: launched(app)
        case NSWorkspace.didActivateApplicationNotification: activated(app)
        default: terminated(app)
        }
    }

    func isRunning(_ id: String) -> Bool {
        apps[id] != nil
    }

    func application(_ id: String) -> NSRunningApplication? {
        apps[id]
    }

    private func id(of app: NSRunningApplication) -> String? {
        if let id = ids[app.processIdentifier] { return id }
        guard let url = app.bundleURL else { return nil }
        let id = url.resolvingSymlinksInPath().path
        ids[app.processIdentifier] = id
        return id
    }

    @discardableResult
    private func track(_ app: NSRunningApplication) -> String? {
        guard app.activationPolicy == .regular, let id = id(of: app) else { return nil }
        if apps[id] == nil { order.append(id) }
        apps[id] = app
        return id
    }

    private func launched(_ app: NSRunningApplication) {
        guard track(app) != nil else { return }
        onChange?(true)
    }

    private func activated(_ app: NSRunningApplication) {
        let isNew = app.activationPolicy == .regular && id(of: app).map { apps[$0] == nil } == true
        guard let id = track(app) else { return }
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
        onChange?(isNew)
    }

    private func terminated(_ app: NSRunningApplication) {
        guard let id = ids.removeValue(forKey: app.processIdentifier), apps[id] === app else { return }
        apps[id] = nil
        order.removeAll { $0 == id }
        onChange?(true)
    }
}
