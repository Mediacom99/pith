import Foundation

/// Scores how well a query matches a `SearchKey`, the way fzf's v2 algorithm does: the best alignment of the query
/// as a subsequence of the text, rewarding word starts and runs of consecutive characters and penalizing gaps.
///
/// Make one per search and use it for every key: its dynamic-programming rows live in a scratch buffer that only
/// grows, so scoring doesn't allocate.
public struct FuzzyMatcher {
    private let query: [UInt8]
    private let queryMask: UInt64
    private var scratch: [Int32] = []

    /// The query is folded like a `SearchKey`; whitespace around it is ignored.
    public init(query: String) {
        var bytes: [UInt8] = []
        var bonus: [UInt8] = []
        Folding.fold(query.trimmingCharacters(in: .whitespacesAndNewlines), bytes: &bytes, bonus: &bonus)
        self.query = bytes
        self.queryMask = Folding.mask(of: bytes)
    }

    public var isEmpty: Bool { query.isEmpty }

    /// The match score, higher is better, or nil when the query isn't a subsequence of the key.
    public mutating func score(_ key: SearchKey) -> Int32? {
        key.bytes.withUnsafeBufferPointer { text in
            key.bonus.withUnsafeBufferPointer { bonus in
                score(text: text, bonus: bonus, mask: key.mask)
            }
        }
    }

    /// The same, for a key stored in a `KeyStore`'s flat buffers.
    mutating func score(text: UnsafeBufferPointer<UInt8>, bonus: UnsafeBufferPointer<UInt8>, mask: UInt64) -> Int32? {
        let length = text.count
        guard !query.isEmpty, query.count <= length, mask & queryMask == queryMask else { return nil }
        if scratch.count < 6 * length {
            scratch = Array(repeating: 0, count: max(6 * length, 2 * scratch.count))
        }
        let query = self.query
        return scratch.withUnsafeMutableBufferPointer { scratch in
            query.withUnsafeBufferPointer { query in
                // Never nil: `scratch` holds at least 6 × the text, which is at least as long as the non-empty query.
                Self.align(query, in: text, bonus: bonus, scratch: scratch.baseAddress!)
            }
        }
    }

    private static let invalid = Int32.min / 2

    private static func align(
        _ query: UnsafeBufferPointer<UInt8>,
        in text: UnsafeBufferPointer<UInt8>,
        bonus: UnsafeBufferPointer<UInt8>,
        scratch: UnsafeMutablePointer<Int32>
    ) -> Int32? {
        let queryLength = query.count

        // Check the query is a subsequence at all, and narrow the work to the columns that can take part:
        // from the first occurrence of its first character to the last occurrence of its last one.
        var first = 0
        var matched = 0
        for column in text.indices where text[column] == query[matched] {
            if matched == 0 { first = column }
            matched += 1
            if matched == queryLength { break }
        }
        guard matched == queryLength else { return nil }
        var last = text.count - 1
        while text[last] != query[queryLength - 1] { last -= 1 }
        let width = last - first + 1

        // One row per query character, two rows alive at a time; index j is text column first + j.
        //   exact[j]   best score with this query character matched at j
        //   gapped[j]  best score with it matched before j and everything after it, up to j, skipped
        //   run[j]     the bonus of the character that opened the consecutive run ending at j
        var exact = scratch
        var gapped = scratch + width
        var run = scratch + 2 * width
        var nextExact = scratch + 3 * width
        var nextGapped = scratch + 4 * width
        var nextRun = scratch + 5 * width

        // The first query character may match anywhere: leading gaps are free.
        for j in 0..<width {
            let columnBonus = Int32(bonus[first + j])
            exact[j] = text[first + j] == query[0] ? Score.match + columnBonus * Score.firstCharMultiplier : invalid
            run[j] = columnBonus
            gapped[j] = j == 0 ? invalid : max(exact[j - 1] + Score.gapStart, gapped[j - 1] + Score.gapExtension)
        }

        for i in 1..<queryLength {
            let character = query[i]
            for j in 0..<width {
                var score = invalid
                var opener: Int32 = 0
                if j > 0, text[first + j] == character {
                    let columnBonus = Int32(bonus[first + j])
                    // Continuing a run: each character earns at least the opener's bonus, unless this one is a
                    // stronger word start, which opens a new run.
                    var runOpener = run[j - 1]
                    let runBonus: Int32
                    if columnBonus >= Int32(Score.boundary), columnBonus > runOpener {
                        runOpener = columnBonus
                        runBonus = columnBonus
                    } else {
                        runBonus = max(columnBonus, runOpener, Score.consecutive)
                    }
                    let consecutive = exact[j - 1] + Score.match + runBonus
                    let afterGap = gapped[j - 1] + Score.match + columnBonus
                    if consecutive >= afterGap {
                        score = consecutive
                        opener = runOpener
                    } else {
                        score = afterGap
                        opener = columnBonus
                    }
                }
                nextExact[j] = score
                nextRun[j] = opener
                nextGapped[j] =
                    j == 0
                    ? invalid : max(nextExact[j - 1] + Score.gapStart, nextGapped[j - 1] + Score.gapExtension)
            }
            swap(&exact, &nextExact)
            swap(&gapped, &nextGapped)
            swap(&run, &nextRun)
        }

        // Trailing gaps are free too.
        var best = invalid
        for j in 0..<width where exact[j] > best { best = exact[j] }
        return best > invalid / 2 ? best : nil
    }
}
