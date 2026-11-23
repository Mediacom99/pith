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
    /// Called with the version that's downloaded and ready to install.
    var onReady: (String) -> Void = { _ in }
    private var updater: SPUUpdater?
    private var schedule = UpdateSchedule()
    /// Installs the downloaded update and relaunches; Sparkle hands it over once the update is ready.
    private var install: (() -> Void)?

    /// Only the copy installed in an Applications folder updates itself, so `make run`'s build in `.build` is never
    /// replaced, and only with a key to check the downloads against.
    static var isEnabled: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && LoginItem.isInApplicationsFolder
    }

    /// Checks for an update when one is due (`UpdateSchedule`). Sparkle starts on the first check, so it reads nothing
    /// at launch.
    func checkIfDue(now: Date = .now) {
        guard Self.isEnabled, install == nil, schedule.take(at: now) else { return }
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
        schedule.failed(at: .now)
    }
}

/// When Pith checks for an update: at the first chance after launch, then at most once a day, and an hour after a
/// check that failed (offline, the site down), rather than a day.
struct UpdateSchedule {
    static let interval: TimeInterval = 86_400
    static let retry: TimeInterval = 3_600
    /// When the next check is due; nil until the first.
    private(set) var next: Date?

    /// Whether a check is due at `now`. If it is, it's taken, and the next one is a day later.
    mutating func take(at now: Date) -> Bool {
        if let next, now < next { return false }
        next = now + Self.interval
        return true
    }

    /// The last check failed: the next is due an hour from `now`.
    mutating func failed(at now: Date) {
        next = now + Self.retry
    }
}
