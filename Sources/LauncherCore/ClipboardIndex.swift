import Foundation

/// The clipboard history in memory (`docs/MILESTONE-3.md` step 3): every clip newest first, each with a search key
/// prepared when it arrives, filtered on every keystroke.
///
/// Words match as written, not fuzzily: in a clip's text (up to 4,096 characters) the letters of almost any short
/// query appear in order somewhere, and scoring thousands of long texts per keystroke would cost too much. Every word
/// of the query must appear in the clip, in any order, ignoring case and accents. Results keep the history's order:
/// newest first, with pinned clips first once you type (decision 33).
public struct ClipboardIndex: Sendable {
    /// Newest first.
    public private(set) var clips: [Clip] = []
    /// `clips[i]`'s search key: folded bytes and their byte set, as in `SearchKey`.
    private var keys: [(bytes: [UInt8], mask: UInt64)] = []
    /// The keys' bytes, all together: how much a search may have to scan.
    private var keyBytes = 0

    /// A search scans in parallel once there's this much text per core to read.
    static let bytesPerChunk = 256 * 1024
    static let cores = ProcessInfo.processInfo.activeProcessorCount

    public init(clips: [Clip] = []) {
        self.clips = clips.sorted(by: Self.newerFirst)
        keys = self.clips.map(Self.key)
        keyBytes = keys.reduce(0) { $0 + $1.bytes.count }
    }

    public var count: Int { clips.count }

    public func position(of id: Int64) -> Int? {
        clips.firstIndex { $0.id == id }
    }

    /// Adds `clip`, or replaces the clip with its id, at its place by when it was copied: usually the top.
    public mutating func insert(_ clip: Clip) {
        remove([clip.id])
        let position = clips.firstIndex { Self.newerFirst(clip, $0) } ?? clips.count
        let key = Self.key(clip)
        clips.insert(clip, at: position)
        keys.insert(key, at: position)
        keyBytes += key.bytes.count
    }

    public mutating func remove(_ ids: some Collection<Int64>) {
        guard !ids.isEmpty else { return }
        let ids = Set(ids)
        for position in clips.indices.reversed() where ids.contains(clips[position].id) {
            clips.remove(at: position)
            keyBytes -= keys.remove(at: position).bytes.count
        }
    }

    public mutating func setPinned(_ pinned: Bool, for id: Int64) {
        if let position = position(of: id) { clips[position].pinned = pinned }
    }

    /// Positions in `clips` of the clips matching `query`, at most `limit`: pinned matches first, then the rest, each
    /// newest first. An empty query lists the newest clips, pinned or not, in their order.
    ///
    /// The newest clips (about `bytesPerChunk` of text) are scanned first. A query that fills the list there, as most
    /// do, then only needs the older pinned clips checked. Otherwise the rest is split into chunks scanned on all cores;
    /// each keeps its order, so joining them in order gives the same list as one scan.
    public func search(_ query: String, limit: Int) -> [Int] {
        let words = QueryTerms(query).words.map { word in
            let bytes = Self.fold(word)
            return (bytes: bytes, mask: Folding.mask(of: bytes))
        }
        guard !words.isEmpty else { return Array(clips.indices.prefix(limit)) }

        let total = clips.count
        let newest = min(total, max(1, total * Self.bytesPerChunk / max(1, keyBytes)))
        var found = [scan(0..<newest, for: words, limit: limit)]
        let left = max(0, limit - found[0].rest.count)
        let older = newest..<total
        let chunks = min(max(1, keyBytes * older.count / max(1, total) / Self.bytesPerChunk), Self.cores)
        if left == 0 || chunks == 1 {
            found.append(scan(older, for: words, limit: left))
        } else {
            var parts = [(pinned: [Int], rest: [Int])](repeating: ([], []), count: chunks)
            parts.withUnsafeMutableBufferPointer { parts in
                // Each chunk reads the shared, unchanging index and writes only its own slot.
                nonisolated(unsafe) let parts = parts
                DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                    let from = older.lowerBound + chunk * older.count / chunks
                    let to = older.lowerBound + (chunk + 1) * older.count / chunks
                    parts[chunk] = scan(from..<to, for: words, limit: left)
                }
            }
            found += parts
        }
        return Array((found.flatMap(\.pinned) + found.flatMap(\.rest)).prefix(limit))
    }

    /// The matches among `positions`, pinned and not, in order. Once `limit` unpinned ones are in, only older pinned
    /// clips can still make the list.
    private func scan(_ positions: Range<Int>, for words: [(bytes: [UInt8], mask: UInt64)], limit: Int) -> (
        pinned: [Int], rest: [Int]
    ) {
        var pinned: [Int] = []
        var rest: [Int] = []
        for position in positions {
            let isPinned = clips[position].pinned
            guard isPinned || rest.count < limit else { continue }
            let key = keys[position]
            guard words.allSatisfy({ $0.mask & key.mask == $0.mask && Self.contains(key.bytes, $0.bytes) }) else {
                continue
            }
            if isPinned { pinned.append(position) } else { rest.append(position) }
        }
        return (pinned, rest)
    }

    /// The first line of `text` containing a word of `query`, for the row to show instead of the first line; nil
    /// without a query or a match.
    public static func matchingLine(in text: String, for query: String) -> Substring? {
        let words = QueryTerms(query).words
        guard !words.isEmpty else { return nil }
        return text.split(whereSeparator: \.isNewline).first { line in
            words.contains { line.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    // MARK: Keys

    /// What a clip is searched by: its text, a link's URL, the files' names. An image has no text to search.
    private static func key(_ clip: Clip) -> (bytes: [UInt8], mask: UInt64) {
        let text =
            switch clip.kind {
            case .text, .richText, .link: clip.text
            case .files:
                clip.text.split(separator: "\n").map { $0.split(separator: "/").last ?? $0 }.joined(separator: "\n")
            case .image: ""
            }
        let bytes = fold(text)
        return (bytes, Folding.mask(of: bytes))
    }

    /// Lowercased, accent-free UTF-8: one Foundation call for the whole text, where the launcher's `Folding` works
    /// character by character to place its match bonuses. Keys and queries fold the same way.
    static func fold(_ text: String) -> [UInt8] {
        if text.utf8.allSatisfy({ $0 < 0x80 }) {
            return text.utf8.map { $0 &- UInt8(ascii: "A") < 26 ? $0 | 0x20 : $0 }
        }
        return Array(text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).utf8)
    }

    private static func contains(_ text: [UInt8], _ word: [UInt8]) -> Bool {
        text.withUnsafeBytes { text in
            word.withUnsafeBytes { word in
                memmem(text.baseAddress, text.count, word.baseAddress, word.count) != nil
            }
        }
    }

    private static func newerFirst(_ a: Clip, _ b: Clip) -> Bool {
        a.copied != b.copied ? a.copied > b.copied : a.id > b.id
    }
}
