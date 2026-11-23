import Foundation
import ServiceManagement

/// Launch at login through `SMAppService`, only for a copy installed in an Applications folder (decision 14), so dev
/// builds in `.build` never leave login items behind.
enum LoginItem {
    /// Whether this copy is installed, in `/Applications` or `~/Applications`, rather than a dev build: only then does
    /// it start at login (decision 14) or update itself (decision 48).
    static var isInApplicationsFolder: Bool {
        let bundle = Bundle.main.bundleURL.path
        let folders = ["/Applications/", URL.homeDirectory.appending(path: "Applications").path + "/"]
        return folders.contains(where: bundle.hasPrefix)
    }

    static func update(enabled: Bool) {
        guard isInApplicationsFolder else {
            Log.app.debug(
                "Not in an Applications folder, launch at login left alone: \(Bundle.main.bundlePath, privacy: .public)"
            )
            return
        }
        Task {
            // Registering talks to the system's login item service: keep it off the main thread.
            await runInBackground(qos: .utility) {
                let service = SMAppService.mainApp
                do {
                    if enabled, service.status != .enabled { try service.register() }
                    if !enabled, service.status == .enabled { try service.unregister() }
                    if service.status == .requiresApproval {
                        Log.app.error("Launch at login needs approval in System Settings › General › Login Items")
                    }
                } catch {
                    Log.app.error("Couldn't update launch at login: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
