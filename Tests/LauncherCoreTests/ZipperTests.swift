import Foundation
import LauncherCore
import TestSupport
import Testing

struct ZipperTests {
    @Test func zipsAFolderNextToItLikeFinder() throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("Report/summary.txt")
        try Data("hello".utf8).write(to: folder.url.appending(path: "Report/summary.txt"))

        let zip = try Zipper.zip(folder.url.appending(path: "Report"))
        #expect(zip.lastPathComponent == "Report.zip")
        #expect(zip.deletingLastPathComponent().path == folder.url.path)

        // It unpacks to the same folder and contents, as Finder's would.
        try folder.makeFolder("Unpacked")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, folder.url.appending(path: "Unpacked").path]
        try ditto.run()
        ditto.waitUntilExit()
        let text = try String(contentsOf: folder.url.appending(path: "Unpacked/Report/summary.txt"), encoding: .utf8)
        #expect(text == "hello")
    }

    @Test func numbersTheZipWhenTheNameIsTaken() throws {
        let folder = try TemporaryDirectory()
        try folder.makeFile("notes.md")
        try folder.makeFile("notes.md.zip")
        try folder.makeFile("notes.md 2.zip")
        #expect(Zipper.destination(for: folder.url.appending(path: "notes.md")).lastPathComponent == "notes.md 3.zip")
        let zip = try Zipper.zip(folder.url.appending(path: "notes.md"))
        #expect(zip.lastPathComponent == "notes.md 3.zip")
    }

    @Test func reportsWhatWentWrong() {
        #expect(throws: Zipper.Failure.self) { try Zipper.zip(URL(filePath: "/nonexistent/thing")) }
    }
}
