import AppKit
import LauncherCore
import UserNotifications

/// What happens after the panel has closed, as a macOS notification: a finished Zip (decision 21) and an action that
/// failed (decision 32). Clicking one reveals its file in Finder. macOS asks for permission the first time; without
/// it, nothing is shown and failures are only logged.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let pathKey = "path"

    /// Set at launch, so a click is handled even after the launcher restarted.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Zips `item` next to itself on a worker, then says how it went.
    func zip(_ item: URL) {
        Task {
            // Asked once, later calls return the stored answer; meanwhile the zip is already under way.
            async let allowed = Self.allowed()
            let result = await runInBackground(qos: .utility) { () -> Result<URL, Zipper.Failure> in
                Result { () throws(Zipper.Failure) in try Zipper.zip(item) }
            }
            let content = UNMutableNotificationContent()
            switch result {
            case .success(let zip):
                content.title = "Zipped"
                content.body = zip.lastPathComponent
                content.userInfo = [Self.pathKey: zip.path]
            case .failure(let failure):
                Log.app.error("Couldn't zip \(item.path, privacy: .public): \(failure.description, privacy: .public)")
                content.title = "Couldn't zip \(item.lastPathComponent)"
                content.body = failure.description
            }
            guard await allowed else { return }
            await Self.post(content)
        }
    }

    /// An action on `item` that failed: what failed as the title ("Couldn't move notes.md to the Trash"), why as the
    /// body. A click reveals the item, to deal with it in Finder.
    func failed(_ title: String, item: URL, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = reason
        content.userInfo = [Self.pathKey: item.path]
        Task {
            guard await Self.allowed() else { return }
            await Self.post(content)
        }
    }

    private static func allowed() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    private static func post(_ content: UNNotificationContent) async {
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // The center calls these on the main thread.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard let path = response.notification.request.content.userInfo[Self.pathKey] as? String else { return }
        await runInBackground(qos: .userInitiated) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
        }
    }
}
