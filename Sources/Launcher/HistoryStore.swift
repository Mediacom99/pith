import Foundation
import LauncherCore

/// The history of what was opened, loaded at launch and saved after every open. Disk work happens on workers.
final class HistoryStore {
    nonisolated static let defaultFile = URL.applicationSupportDirectory.appending(path: "pith/history.json")

    private(set) var history = History()
    private let file: URL
    /// Serial, so saves land in order.
    private let writer = DispatchQueue(label: "launcher.history", qos: .utility)

    init(file: URL = HistoryStore.defaultFile) {
        self.file = file
    }

    /// Called once at launch, before the hotkey is registered, so nothing can be recorded before it lands.
    func load() async {
        let file = self.file
        history = await runInBackground(qos: .userInitiated) {
            var history = Self.read(file)
            // Files and folders deleted since: forget them, so `recent` never lists what's gone.
            for id in Array(history.ids) {
                if let path = Item(fileID: id)?.url?.path, !FileManager.default.fileExists(atPath: path) {
                    history.remove(id)
                }
            }
            return history
        }
    }

    func record(_ id: String, at date: Date = .now) {
        history.record(id, at: date)
        let snapshot = history
        let file = self.file
        writer.async { Self.write(snapshot, to: file) }
    }

    /// Forgets deleted files and folders, saving only if that changed anything.
    func forget(paths: [String]) {
        var updated = history
        updated.forget(paths: paths)
        guard updated != history else { return }
        history = updated
        let snapshot = updated
        let file = self.file
        writer.async { Self.write(snapshot, to: file) }
    }

    /// Waits for pending saves: called when the app quits.
    func flush() {
        writer.sync {}
    }

    private nonisolated static func read(_ file: URL) -> History {
        guard let data = try? Data(contentsOf: file) else { return History() }
        do {
            return try JSONDecoder().decode(History.self, from: data)
        } catch {
            Log.app.error("Couldn't read the history, starting over: \(error.localizedDescription, privacy: .public)")
            return History()
        }
    }

    private nonisolated static func write(_ history: History, to file: URL) {
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(history).write(to: file, options: .atomic)
        } catch {
            Log.app.error("Couldn't save the history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
