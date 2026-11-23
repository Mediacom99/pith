import CryptoKit
import Foundation

/// The clipboard history on disk (`docs/MILESTONE-3.md` step 1): a SQLite database for the clips, their text and what
/// a paste puts back, and an `images` folder beside it with each image and its two thumbnails.
///
/// Owns its database on a private serial queue: every call runs there, one at a time, off the main thread and off
/// Swift's cooperative pool. The database opens on the first call.
public final class ClipboardStore: @unchecked Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String

        public init(description: String) {
            self.description = description
        }
    }

    /// How much history is kept: whichever limit is hit first drops the oldest unpinned clips (decision 37).
    public struct Retention: Sendable, Equatable {
        public var maxBytes: Int
        public var maxAge: TimeInterval

        public init(maxBytes: Int, maxAge: TimeInterval) {
            self.maxBytes = maxBytes
            self.maxAge = maxAge
        }
    }

    /// A row's image thumbnail: 20 pt at 2x.
    public static let rowThumbnailPixels = 40
    /// The preview box on the tile, 320 × 156 pt at 2x.
    public static let previewPixels = (width: 640, height: 312)

    public let folder: URL
    // State below is only touched on `queue`.
    private let queue = DispatchQueue(label: "launcher.clipboard", qos: .userInitiated)
    private var openDatabase: SQLiteDatabase?

    public init(folder: URL) {
        self.folder = folder
    }

    // MARK: Files

    /// An image clip's image, as PNG.
    public func imageFile(of id: Int64) -> URL { images.appending(path: "\(id).png") }

    /// An image clip's row thumbnail, `rowThumbnailPixels` square.
    public func rowThumbnail(of id: Int64) -> URL { images.appending(path: "\(id)-row.png") }

    /// An image clip's preview, fitted into `previewPixels`.
    public func previewThumbnail(of id: Int64) -> URL { images.appending(path: "\(id)-preview.png") }

    private var images: URL { folder.appending(path: "images") }

    // MARK: Reading

    /// Every clip, newest first. Also removes image files a crash left without their clip.
    public func load() async throws(Failure) -> [Clip] {
        try await run { () throws(Failure) in
            let database = try self.database()
            let statement = try database.prepare(
                "SELECT \(Self.clipColumns) FROM clip ORDER BY copied DESC, id DESC")
            try statement.bind([.integer(Int64(Clip.textLimit))])
            var clips: [Clip] = []
            while try statement.step() { clips.append(Self.clip(statement)) }
            self.removeOrphanFiles(keeping: Set(clips.lazy.filter { $0.kind == .image }.map(\.id)))
            return clips
        }
    }

    /// What a paste of clip `id` puts back on the pasteboard: each item's representations, in their order. An image
    /// comes first in the first item, as PNG. Fails when nothing of the clip is left to put back, or an image clip's
    /// image file is gone, so a paste never empties the clipboard.
    public func items(of id: Int64) async throws(Failure) -> [[Representation]] {
        try await run { () throws(Failure) in
            let clip = try self.database().prepare("SELECT kind FROM clip WHERE id = ?")
            try clip.bind([.integer(id)])
            guard try clip.step() else { throw Failure(description: "it's no longer in the history") }
            let isImage = clip.text(0) == Clip.Kind.image.rawValue
            let statement = try self.database().prepare(
                "SELECT item, type, data FROM representation WHERE clip = ? ORDER BY item, position")
            try statement.bind([.integer(id)])
            var items: [[Representation]] = []
            while try statement.step() {
                let item = Int(statement.integer(0))
                while items.count <= item { items.append([]) }
                items[item].append(Representation(type: statement.text(1), data: statement.blob(2)))
            }
            if let image = try? Data(contentsOf: self.imageFile(of: id)) {
                if items.isEmpty { items.append([]) }
                items[0].insert(Representation(type: "public.png", data: image), at: 0)
            } else if isImage {
                throw Failure(description: "its image file is gone")
            }
            guard !items.isEmpty else { throw Failure(description: "nothing of it is left to paste") }
            return items
        }
    }

    /// The whole text of clip `id`, where `Clip.text` has only its start.
    public func text(of id: Int64) async throws(Failure) -> String {
        try await run { () throws(Failure) in
            let statement = try self.database().prepare("SELECT text FROM clip WHERE id = ?")
            try statement.bind([.integer(id)])
            guard try statement.step() else { throw Failure(description: "clip \(id) isn't in the history") }
            return statement.text(0)
        }
    }

    // MARK: Writing

    /// Stores what was just copied and returns its clip. If the same content is already in the history, that clip
    /// moves to `date` and keeps its pin, instead of a second copy being stored; it takes the new source, unless that
    /// one is unknown.
    public func add(_ content: ClipContent, from source: String?, at date: Date) async throws(Failure) -> Clip {
        try await run { () throws(Failure) in
            let database = try self.database()
            let hash = Self.hash(content)
            let sourceValue: SQLiteDatabase.Value = source.map { .text($0) } ?? .null
            let existing = try database.prepare("SELECT id FROM clip WHERE hash = ?")
            try existing.bind([.blob(hash)])
            if try existing.step() {
                let id = existing.integer(0)
                existing.reset()
                try database.prepare("UPDATE clip SET copied = ?, source = coalesce(?, source) WHERE id = ?")
                    .run([.real(date.timeIntervalSince1970), sourceValue, .integer(id)])
                return try self.clip(id, in: database)
            }

            let rendered: ImageThumbnails.Rendered?
            if let image = content.image {
                rendered = ImageThumbnails.render(
                    image, rowPixels: Self.rowThumbnailPixels, preview: Self.previewPixels)
                guard rendered != nil else { throw Failure(description: "the copied image couldn't be read") }
            } else {
                rendered = nil
            }
            var size = content.text.utf8.count + content.items.joined().reduce(0) { $0 + $1.data.count }
            if let image = content.image, let rendered {
                size += image.count + rendered.row.count + rendered.preview.count
            }

            var written: [URL] = []
            do throws(Failure) {
                return try database.transaction { () throws(Failure) in
                    try database.prepare(
                        """
                        INSERT INTO clip (kind, copied, source, pinned, size, hash, text, lines, width, height)
                        VALUES (?, ?, ?, 0, ?, ?, ?, ?, ?, ?)
                        """
                    ).run([
                        .text(content.kind.rawValue), .real(date.timeIntervalSince1970), sourceValue,
                        .integer(Int64(size)), .blob(hash), .text(content.text),
                        .integer(Int64(Clip.lineCount(of: content.text))),
                        .integer(Int64(rendered?.width ?? 0)), .integer(Int64(rendered?.height ?? 0)),
                    ])
                    let id = database.lastInsertedRow
                    let insert = try database.prepare(
                        "INSERT INTO representation (clip, item, position, type, data) VALUES (?, ?, ?, ?, ?)")
                    for (item, representations) in content.items.enumerated() {
                        for (position, representation) in representations.enumerated() {
                            try insert.run([
                                .integer(id), .integer(Int64(item)), .integer(Int64(position)),
                                .text(representation.type), .blob(representation.data),
                            ])
                        }
                    }
                    if let image = content.image, let rendered {
                        for (data, file) in [
                            (image, self.imageFile(of: id)), (rendered.row, self.rowThumbnail(of: id)),
                            (rendered.preview, self.previewThumbnail(of: id)),
                        ] {
                            do {
                                try data.write(to: file, options: .atomic)
                            } catch {
                                throw Failure(description: "couldn't save the image: \(error.localizedDescription)")
                            }
                            written.append(file)
                        }
                    }
                    return try self.clip(id, in: database)
                }
            } catch {
                for file in written { try? FileManager.default.removeItem(at: file) }
                throw error
            }
        }
    }

    /// Moves clip `id` to `date`, as if copied again: for a paste the recorder doesn't see (plain text).
    public func touch(_ id: Int64, at date: Date) async throws(Failure) -> Clip {
        try await run { () throws(Failure) in
            let database = try self.database()
            try database.prepare("UPDATE clip SET copied = ? WHERE id = ?").run([
                .real(date.timeIntervalSince1970), .integer(id),
            ])
            return try self.clip(id, in: database)
        }
    }

    public func setPinned(_ pinned: Bool, for id: Int64) async throws(Failure) {
        try await run { () throws(Failure) in
            try self.database().prepare("UPDATE clip SET pinned = ? WHERE id = ?")
                .run([.integer(pinned ? 1 : 0), .integer(id)])
        }
    }

    public func delete(_ id: Int64) async throws(Failure) {
        try await run { () throws(Failure) in try self.remove([id]) }
    }

    /// Whether recording is paused (decision 44): a `paused` file beside the database, so it lasts through a relaunch.
    public func isPaused() async -> Bool {
        let file = pausedFile
        return (try? await run { FileManager.default.fileExists(atPath: file.path) }) ?? false
    }

    public func setPaused(_ paused: Bool) async throws(Failure) {
        let (folder, file) = (folder, pausedFile)
        try await run { () throws(Failure) in
            do {
                if paused {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try Data().write(to: file)
                } else if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                throw Failure(
                    description:
                        "couldn't save that recording is \(paused ? "paused" : "on"): \(error.localizedDescription)")
            }
        }
    }

    private var pausedFile: URL { folder.appending(path: "paused") }

    /// Deletes every clip that isn't pinned and returns their ids.
    public func clear() async throws(Failure) -> [Int64] {
        try await run { () throws(Failure) in
            let statement = try self.database().prepare("SELECT id FROM clip WHERE pinned = 0")
            try statement.bind([])
            var ids: [Int64] = []
            while try statement.step() { ids.append(statement.integer(0)) }
            try self.remove(ids)
            return ids
        }
    }

    /// Applies `retention` and returns the ids it deleted: unpinned clips older than its age go, then the oldest
    /// unpinned ones until the history fits its size. Pinned clips always stay.
    public func prune(_ retention: Retention, now: Date) async throws(Failure) -> [Int64] {
        try await run { () throws(Failure) in
            let statement = try self.database().prepare(
                "SELECT id, copied, size, pinned FROM clip ORDER BY copied, id")
            try statement.bind([])
            var rows: [(id: Int64, copied: Double, size: Int, pinned: Bool)] = []
            while try statement.step() {
                rows.append(
                    (statement.integer(0), statement.real(1), Int(statement.integer(2)), statement.integer(3) != 0))
            }
            var total = rows.reduce(0) { $0 + $1.size }
            let oldest = now.timeIntervalSince1970 - retention.maxAge
            var removed: [Int64] = []
            for row in rows where !row.pinned && (row.copied < oldest || total > retention.maxBytes) {
                removed.append(row.id)
                total -= row.size
            }
            try self.remove(removed)
            return removed
        }
    }

    // MARK: On the queue

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws(Failure) -> T) async throws(Failure) -> T {
        let result: Result<T, Failure> = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: Result { () throws(Failure) in try work() }) }
        }
        return try result.get()
    }

    /// The open database, opened and set up on first use.
    private func database() throws(Failure) -> SQLiteDatabase {
        if let openDatabase { return openDatabase }
        do {
            try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        } catch {
            throw Failure(description: "couldn't create \(images.path): \(error.localizedDescription)")
        }
        let database = try SQLiteDatabase(path: folder.appending(path: "history.sqlite").path)
        let version = try database.prepare("PRAGMA user_version")
        try version.bind([])
        _ = try version.step()
        let schema = version.integer(0)
        version.reset()
        switch schema {
        case 0:
            // auto_vacuum only takes effect before the first table exists.
            try database.execute(
                """
                PRAGMA auto_vacuum = INCREMENTAL;
                CREATE TABLE clip (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    kind TEXT NOT NULL,
                    copied REAL NOT NULL,
                    source TEXT,
                    pinned INTEGER NOT NULL,
                    size INTEGER NOT NULL,
                    hash BLOB NOT NULL UNIQUE,
                    text TEXT NOT NULL,
                    lines INTEGER NOT NULL,
                    width INTEGER NOT NULL,
                    height INTEGER NOT NULL
                );
                CREATE INDEX clip_copied ON clip (copied);
                CREATE TABLE representation (
                    clip INTEGER NOT NULL REFERENCES clip (id) ON DELETE CASCADE,
                    item INTEGER NOT NULL,
                    position INTEGER NOT NULL,
                    type TEXT NOT NULL,
                    data BLOB NOT NULL,
                    PRIMARY KEY (clip, item, position)
                ) WITHOUT ROWID;
                PRAGMA user_version = 1;
                """)
        case 1: break
        case let other: throw Failure(description: "the clipboard history is from a newer Pith (version \(other))")
        }
        try database.execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;")
        openDatabase = database
        return database
    }

    /// `octet_length` reads the text's size from the row without loading the text.
    private static let clipColumns =
        "id, kind, copied, source, pinned, size, substr(text, 1, ?), lines, width, height, octet_length(text)"

    private static func clip(_ row: SQLiteDatabase.Statement) -> Clip {
        Clip(
            id: row.integer(0), kind: Clip.Kind(rawValue: row.text(1)) ?? .text,
            copied: Date(timeIntervalSince1970: row.real(2)), source: row.isNull(3) ? nil : row.text(3),
            pinned: row.integer(4) != 0, size: Int(row.integer(5)), text: row.text(6), lines: Int(row.integer(7)),
            textBytes: Int(row.integer(10)), pixelWidth: Int(row.integer(8)), pixelHeight: Int(row.integer(9)))
    }

    private func clip(_ id: Int64, in database: SQLiteDatabase) throws(Failure) -> Clip {
        let statement = try database.prepare("SELECT \(Self.clipColumns) FROM clip WHERE id = ?")
        try statement.bind([.integer(Int64(Clip.textLimit)), .integer(id)])
        guard try statement.step() else { throw Failure(description: "clip \(id) vanished") }
        return Self.clip(statement)
    }

    /// Deletes clips `ids`, their representations and their image files, then gives the freed pages back to the disk.
    private func remove(_ ids: [Int64]) throws(Failure) {
        guard !ids.isEmpty else { return }
        let database = try database()
        try database.transaction { () throws(Failure) in
            let delete = try database.prepare("DELETE FROM clip WHERE id = ?")
            for id in ids { try delete.run([.integer(id)]) }
        }
        try database.execute("PRAGMA incremental_vacuum")
        for id in ids {
            for file in [imageFile(of: id), rowThumbnail(of: id), previewThumbnail(of: id)] {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Removes files in `images` whose clip isn't in `ids`: what a crash between writing them and saving the clip
    /// left behind.
    private func removeOrphanFiles(keeping ids: Set<Int64>) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: images.path) else { return }
        for name in names {
            let id = name.prefix { $0.isNumber }
            if let id = Int64(id), ids.contains(id) { continue }
            try? FileManager.default.removeItem(at: images.appending(path: name))
        }
    }

    /// Identifies content regardless of when or where it was copied: its kind, every representation and the image.
    private static func hash(_ content: ClipContent) -> Data {
        var hasher = SHA256()
        func add(_ data: Data) {
            withUnsafeBytes(of: UInt64(data.count).littleEndian) { hasher.update(bufferPointer: $0) }
            hasher.update(data: data)
        }
        add(Data(content.kind.rawValue.utf8))
        for item in content.items {
            add(Data("item".utf8))
            for representation in item {
                add(Data(representation.type.utf8))
                add(representation.data)
            }
        }
        if let image = content.image { add(image) }
        return Data(hasher.finalize())
    }
}
