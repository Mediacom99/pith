import AppKit
import LauncherCore
import UserNotifications

/// Zips in the background and says so with a notification when it's done (decision 21). Clicking the notification
/// reveals the zip in Finder. macOS asks for permission the first time; without it, the zip just appears.
final class ZipNotifier: NSObject, UNUserNotificationCenterDelegate {
    private nonisolated static let pathKey = "path"

    /// Set at launch, so a click is handled even after the launcher restarted.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    func zip(_ item: URL) {
        Task {
            let center = UNUserNotificationCenter.current()
            // Asked once, later calls return the stored answer; meanwhile the zip is already under way.
            async let allowed = (try? center.requestAuthorization(options: [.alert])) ?? false
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
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
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
