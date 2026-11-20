import Foundation

/// Compresses a file or folder the way Finder's Compress does (FEATURES.md §4.4). Blocks until done: call it on a
/// worker.
public enum Zipper {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Writes `item`'s zip next to it and returns where: `name.zip`, or `name 2.zip`, `name 3.zip`… when taken.
    public static func zip(_ item: URL) throws(Failure) -> URL {
        let destination = destination(for: item)
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", item.path, destination.path]
        let errors = Pipe()
        ditto.standardError = errors
        do {
            try ditto.run()
        } catch {
            throw Failure(description: "couldn't run ditto: \(error.localizedDescription)")
        }
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: destination)
            let text = String(decoding: message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(description: text.isEmpty ? "ditto failed (\(ditto.terminationStatus))" : text)
        }
        return destination
    }

    /// Finder's naming: `report.pdf` → `report.pdf.zip`, `Folder` → `Folder.zip`, then `… 2.zip` and up.
    public static func destination(for item: URL) -> URL {
        let folder = item.deletingLastPathComponent()
        let name = item.lastPathComponent
        var candidate = folder.appending(path: name + ".zip")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(name) \(number).zip")
            number += 1
        }
        return candidate
    }
}
