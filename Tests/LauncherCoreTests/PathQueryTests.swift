import Foundation
import LauncherCore
import TestSupport
import Testing

/// Paths typed as in a terminal (decision 81).
struct PathQueryTests {
    @Test func aPathIsWhatStartsWithASlashOrTilde() throws {
        let documents = try #require(PathQuery("~/Documents/re", home: "/Users/me"))
        #expect(documents.typedFolder == "~/Documents/")
        #expect(documents.folder == "/Users/me/Documents/")
        #expect(documents.prefix == "re")
        #expect(PathQuery("~/", home: "/Users/me")?.folder == "/Users/me/")
        #expect(PathQuery("/", home: "/Users/me") == PathQuery("/", home: "/elsewhere"), "no home in it")
        #expect(PathQuery("/")?.folder == "/")
        #expect(PathQuery("/")?.prefix == "")
        #expect(PathQuery("/Users//me/x", home: "/Users/me")?.folder == "/Users/me/", "doubled slashes are one")
        #expect(PathQuery("acme/deploy") == nil, "path words, not a path (decision 23)")
        #expect(PathQuery("~") == nil)
        #expect(PathQuery("~docs") == nil)
    }

    @Test func tabFillsInTheNameAndAFolderItsSlash() throws {
        let query = try #require(PathQuery("~/Doc", home: "/Users/me"))
        #expect(query.completed(with: "Documents", isFolder: true) == "~/Documents/")
        #expect(query.completed(with: "Docker.dmg", isFolder: false) == "~/Docker.dmg")
    }

    /// The folder's contents as Finder sorts them, narrowed to the names that start with what's typed, ignoring case
    /// and accents. Hidden names once a dot is typed; a package is a file, a link to a folder is a folder.
    @Test func listsAFolderAndNarrowsIt() throws {
        let folder = try TemporaryDirectory()
        for file in ["Report.pdf", "résumé.txt", ".hidden", "notes.md"] { try folder.makeFile(file) }
        try folder.makeFolder("Reports/2026")
        try folder.makeFolder("Gizmo.app/Contents")
        try FileManager.default.createSymbolicLink(
            at: folder.url.appending(path: "Linked"), withDestinationURL: folder.url.appending(path: "Reports"))

        let listing = FolderListing(reading: folder.url.path + "/")
        let all = listing.matching("", limit: 50)
        #expect(all.map(\.name) == ["Gizmo.app", "Linked", "notes.md", "Report.pdf", "Reports", "résumé.txt"])
        #expect(all.filter(\.isFolder).map(\.name) == ["Linked", "Reports"])
        #expect(listing.matching("RE", limit: 50).map(\.name) == ["Report.pdf", "Reports", "résumé.txt"])
        #expect(listing.matching("resu", limit: 50).map(\.name) == ["résumé.txt"])
        #expect(listing.matching(".", limit: 50).map(\.name) == [".hidden"])
        #expect(listing.matching("re", limit: 2).count == 2)
        #expect(listing.path(of: all[0]) == folder.url.path + "/Gizmo.app")
        #expect(FolderListing(reading: folder.url.path + "/missing/").entries.isEmpty)
    }
}
