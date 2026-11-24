import Foundation

/// One entry of the clipboard history, as the panel lists it (`FEATURES.md` §5, `docs/BRIEF-CLIPBOARD.md`). What a
/// paste puts back stays in the store until it's asked for.
public struct Clip: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case text
        case richText = "rich-text"
        case link
        case image
        case files
    }

    /// How much of a clip's text is kept in memory, in characters: enough to search it and preview its first lines.
    /// The whole text stays in the store.
    public static let textLimit = 4096
    /// The same for files' paths, one per line: about 2,500 of them.
    public static let pathsLimit = 262_144

    public let id: Int64
    public var kind: Kind
    /// When it was last copied: copying the same content again moves it here.
    public var copied: Date
    /// The bundle id of the app it was copied from, when known.
    public var source: String?
    public var pinned: Bool
    /// Bytes on disk: its text, what a paste puts back, and for an image the image and its thumbnails.
    public var size: Int
    /// The start of its text (`textLimit` characters, `pathsLimit` for files): the text itself, a link's URL, or the
    /// files' paths one per line. Empty for an image.
    public var text: String
    /// How many lines the whole text has, and its size in bytes.
    public var lines: Int
    public var textBytes: Int
    /// An image's size in pixels, upright; zero for other kinds.
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(
        id: Int64, kind: Kind, copied: Date, source: String?, pinned: Bool, size: Int, text: String, lines: Int,
        textBytes: Int? = nil, pixelWidth: Int = 0, pixelHeight: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.copied = copied
        self.source = source
        self.pinned = pinned
        self.size = size
        self.text = text
        self.lines = lines
        self.textBytes = textBytes ?? text.utf8.count
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// The number of lines in `text`, not counting an empty one after a final line break.
    public static func lineCount(of text: String) -> Int {
        var lines = 0
        var last: UInt8 = 0
        for byte in text.utf8 {
            if byte == 0x0A { lines += 1 }
            last = byte
        }
        return text.isEmpty ? 0 : lines + (last == 0x0A ? 0 : 1)
    }
}

/// One pasteboard type and its data, as an app offered it.
public struct Representation: Sendable, Equatable {
    /// A pasteboard type: `public.utf8-plain-text`, `public.rtf`, `public.file-url`…
    public var type: String
    public var data: Data

    public init(type: String, data: Data) {
        self.type = type
        self.data = data
    }
}

/// What one copy holds, ready to store.
public struct ClipContent: Sendable, Equatable {
    public var kind: Clip.Kind
    /// The text it carries: the text itself, a link's URL, or the files' paths one per line. Empty for an image.
    public var text: String
    /// What a paste puts back: each pasteboard item's representations, in the order the app offered them. An image's
    /// own data isn't here but in `image`.
    public var items: [[Representation]]
    /// An image, as PNG.
    public var image: Data?

    public init(kind: Clip.Kind, text: String, items: [[Representation]], image: Data? = nil) {
        self.kind = kind
        self.text = text
        self.items = items
        self.image = image
    }
}
