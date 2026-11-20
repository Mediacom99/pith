import Foundation

/// A fresh folder under the system temporary directory, deleted when it goes out of scope.
public struct TemporaryDirectory: ~Copyable {
    public let url: URL

    public init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LauncherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// The path with symlinks resolved (/private/var/…), as FSEvents reports it.
    public var canonicalPath: String {
        guard let real = realpath(url.path, nil) else { return url.path }
        defer { free(real) }
        return String(cString: real)
    }

    public func makeFolder(_ path: String) throws {
        try FileManager.default.createDirectory(at: url.appending(path: path), withIntermediateDirectories: true)
    }

    /// An empty file, with its folders.
    public func makeFile(_ path: String) throws {
        let file = url.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
