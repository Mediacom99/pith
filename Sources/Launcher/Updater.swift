import AppKit
import Sparkle

/// Updates (decision 48). Sparkle reads the feed set in Info.plist (`SUFeedURL`), checks each download against the key
/// there (`SUPublicEDKey`) and the app's own signature, and installs it.
///
/// Its schedule is off (`SUEnableAutomaticChecks`): Pith asks after the panel closes, at most once a day, so there's
/// no timer and nothing on the ⌘P path. A found update downloads in the background (`SUAutomaticallyUpdate`), then
/// waits: the launcher lists Update Pith, which installs it and relaunches, and Sparkle installs it anyway when Pith
/// quits.
///
/// How it went is a notification (decision 49): the next launch compares its build with the update that was ready,
/// and a found update that fails to download, verify or install says so at once. A check that can't reach the site
/// stays quiet and is tried again an hour later.
final class Updater: NSObject, SPUUpdaterDelegate {
    /// Called with the version that's downloaded and ready to install, and with nil when it no longer is.
    var onReady: (String?) -> Void = { _ in }
    /// How an update went: at launch after one was ready, or as soon as a found update fails.
    var onResult: (UpdateResult) -> Void = { _ in }
    private var updater: SPUUpdater?
    private var schedule = UpdateSchedule()
    /// The version the current check found, for a failure to name.
    private var found: String?
    /// Whether the current check was asked for (Check for Updates), so its outcome is reported whatever it is.
    private var asked = false
    /// Failed updates already said, so a scheduled check failing on the same one again says nothing.
    private var failures = UpdateFailures()
    /// The update that's ready, saved for the next launch to say how it went.
    private var pending: PendingUpdate?
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
        check()
    }

    /// Checks right away, whatever the schedule (Check for Updates, decision 50): a notification says whether an
    /// update is ready, Pith is up to date, or the check failed. A check already under way reports instead.
    func checkNow() {
        guard Self.isEnabled, install == nil else { return }
        schedule.takeNow(at: .now)
        asked = true
        check()
    }

    private func check() {
        if updater == nil {
            let bundle = Bundle.main
            let updater = SPUUpdater(
                hostBundle: bundle, applicationBundle: bundle,
                userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil), delegate: self)
            do {
                try updater.start()
            } catch {
                Log.app.error("Couldn't start the updater: \(error.localizedDescription, privacy: .public)")
                report(.checkFailed(reason: error.localizedDescription))
                return
            }
            self.updater = updater
        }
        // A check under way carries on, and reports if this one was asked for.
        guard let updater, !updater.sessionInProgress else { return }
        found = nil
        updater.checkForUpdatesInBackground()
    }

    /// Installs the update that's ready, and relaunches into it. It's saved as asked for first, so a relaunch that
    /// isn't into it reports a failure.
    func installNow() {
        guard let install, var request = pending else { return }
        request.requested = true
        pending = request
        let saved = request
        Task {
            await runInBackground(qos: .userInitiated) { saved.save() }
            install()
        }
    }

    /// Says how the update that was ready before this launch went, once.
    func reportLastUpdate() {
        guard Self.isEnabled else { return }
        let bundle = Bundle.main
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let version = Self.version
        Task {
            let last = await runInBackground(qos: .utility) { PendingUpdate.take() }
            if let result = last?.result(runningBuild: build, runningVersion: version) { onResult(result) }
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// The outcome of a check that was asked for; the scheduled ones only report failed updates.
    private func report(_ result: UpdateResult) {
        guard asked else { return }
        asked = false
        onResult(result)
    }

    /// Whether `error` is about an update that was found (its download, its signature, its install) rather than about
    /// the feed, which is only tried again later. Canceling an install isn't a failure.
    static func isUpdateProblem(_ error: NSError) -> Bool {
        let canceled = [SUError.installationCanceledError, .installationAuthorizeLaterError].map { Int($0.rawValue) }
        return error.domain == SUSparkleErrorDomain && error.code >= Int(SUError.temporaryDirectoryError.rawValue)
            && !canceled.contains(error.code)
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        found = item.displayVersionString
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        report(.upToDate(Self.version))
    }

    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        install = immediateInstallHandler
        let pending = PendingUpdate(build: item.versionString, version: item.displayVersionString)
        self.pending = pending
        Task { await runInBackground(qos: .utility) { pending.save() } }
        Log.app.info("Pith \(item.displayVersionString, privacy: .public) is downloaded and ready to install")
        onReady(item.displayVersionString)
        report(.ready(item.displayVersionString))
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let error = error as NSError
        guard !(error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)) else {
            return
        }
        Log.app.error("Couldn't update: \(error.localizedDescription, privacy: .public)")
        schedule.failed(at: .now)
        guard Self.isUpdateProblem(error) else {
            // The error beneath Sparkle's says what went wrong ("A server with the specified hostname could not be
            // found.").
            let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
            report(.checkFailed(reason: (underlying ?? error).localizedDescription))
            return
        }
        let wasAsked = asked
        asked = false
        // It's dropped: the next check finds it again and downloads it from the start.
        if install != nil {
            install = nil
            onReady(nil)
        }
        pending = nil
        Task { await runInBackground(qos: .utility) { _ = PendingUpdate.take() } }
        let version = found ?? "a new version"
        guard failures.shouldSay(version, asked: wasAsked) else { return }
        onResult(.failed(to: version, reason: error.localizedDescription))
    }
}

/// Which failed updates were said: a scheduled check that fails on the same update again (a bad signature, every
/// hour) says nothing more; one that was asked for always says how it went.
struct UpdateFailures {
    private var said: Set<String> = []

    mutating func shouldSay(_ version: String, asked: Bool) -> Bool {
        said.insert(version).inserted || asked
    }
}

/// How an update went (decision 49), or what Check for Updates found (decision 50), for a notification.
enum UpdateResult: Equatable {
    case updated(to: String)
    case failed(to: String, reason: String)
    case ready(String)
    /// With the version that's running.
    case upToDate(String)
    case checkFailed(reason: String)

    var title: String {
        switch self {
        case .updated(let version): "Pith updated to \(version)"
        case .failed(let version, _): "Couldn't update Pith to \(version)"
        case .ready(let version): "Pith \(version) is ready"
        case .upToDate: "Pith is up to date"
        case .checkFailed: "Couldn't check for updates"
        }
    }

    var body: String {
        switch self {
        case .updated: ""
        case .failed(_, let reason), .checkFailed(let reason): reason
        case .ready: "Update Pith in the launcher restarts into it."
        case .upToDate(let version): "\(version) is the newest version."
        }
    }
}

/// An update that was ready to install, kept in Pith's defaults so the next launch can say how it went.
nonisolated struct PendingUpdate: Equatable, Sendable {
    private static let key = "PendingUpdate"
    /// Its build number (`CFBundleVersion`), which tells it apart, and the version people see.
    var build: String
    var version: String
    /// Whether Update Pith was chosen. One that was to install on quit and didn't is just found again by the next
    /// check, so that isn't reported.
    var requested = false

    /// How it went, given the build that's running now; nil when there's nothing to say.
    func result(runningBuild: String, runningVersion: String) -> UpdateResult? {
        if runningBuild == build { return .updated(to: version) }
        guard requested else { return nil }
        return .failed(to: version, reason: "Pith is still \(runningVersion), and tries again on its next check.")
    }

    func save() {
        UserDefaults.standard.set(["build": build, "version": version, "requested": requested], forKey: Self.key)
    }

    /// The saved one, which is then forgotten.
    static func take() -> PendingUpdate? {
        let defaults = UserDefaults.standard
        guard let saved = defaults.dictionary(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        guard let build = saved["build"] as? String, let version = saved["version"] as? String else { return nil }
        return PendingUpdate(build: build, version: version, requested: saved["requested"] as? Bool ?? false)
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
        takeNow(at: now)
        return true
    }

    /// A check at `now` that was asked for, due or not: the next one is a day later.
    mutating func takeNow(at now: Date) {
        next = now + Self.interval
    }

    /// The last check failed: the next is due an hour from `now`.
    mutating func failed(at now: Date) {
        next = now + Self.retry
    }
}
