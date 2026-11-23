import AppKit
import Sparkle

/// Updates (decision 48). Sparkle reads the feed set in Info.plist (`SUFeedURL`), checks each download against the key
/// there (`SUPublicEDKey`) and the app's own signature, and installs it.
///
/// Its schedule is off (`SUEnableAutomaticChecks`): Pith asks after the panel closes, at most once a day, so there's
/// no timer and nothing on the ⌘P path. A found update downloads in the background (`SUAutomaticallyUpdate`), then
/// waits: the launcher lists Update Pith, which installs it and relaunches, and Sparkle installs it anyway when Pith
/// quits.
final class Updater: NSObject, SPUUpdaterDelegate {
    static let interval: TimeInterval = 86_400

    /// Called with the version that's downloaded and ready to install.
    var onReady: (String) -> Void = { _ in }
    private var updater: SPUUpdater?
    private var lastCheck: Date?
    /// Installs the downloaded update and relaunches; Sparkle hands it over once the update is ready.
    private var install: (() -> Void)?

    /// Only the copy installed in an Applications folder updates itself, so `make run`'s build in `.build` is never
    /// replaced, and only with a key to check the downloads against.
    static var isEnabled: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && LoginItem.isInApplicationsFolder
    }

    /// Checks for an update when a day has passed since the last check, or none was made since launch. Sparkle starts
    /// on the first one, so it reads nothing at launch.
    func checkIfDue(now: Date = .now) {
        guard Self.isEnabled, install == nil else { return }
        if let lastCheck, now.timeIntervalSince(lastCheck) < Self.interval { return }
        lastCheck = now
        if updater == nil {
            let bundle = Bundle.main
            let updater = SPUUpdater(
                hostBundle: bundle, applicationBundle: bundle,
                userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil), delegate: self)
            do {
                try updater.start()
            } catch {
                Log.app.error("Couldn't start the updater: \(error.localizedDescription, privacy: .public)")
                return
            }
            self.updater = updater
        }
        updater?.checkForUpdatesInBackground()
    }

    /// Installs the update that's ready, and relaunches into it.
    func installNow() {
        install?()
    }

    // MARK: SPUUpdaterDelegate

    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        install = immediateInstallHandler
        Log.app.info("Pith \(item.displayVersionString, privacy: .public) is downloaded and ready to install")
        onReady(item.displayVersionString)
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let error = error as NSError
        guard !(error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)) else {
            return
        }
        Log.app.error("Couldn't update: \(error.localizedDescription, privacy: .public)")
    }
}
