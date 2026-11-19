/// A query split into words, at spaces and at `/`: "budget review" and "acme/deploy" are two words each.
///
/// Every word must match, in any order. For files, the last word must match the name, and the others may match the
/// name or a folder above it, so "acme deploy" finds deploy.sh in ~/Projects/Acme, while "acme" alone still finds only
/// what's named acme. `~` and `.` are skipped, so a path like `~/Downloads/contr` works too.
struct QueryTerms {
    let words: [String]

    init(_ query: String) {
        words = query.split { $0.isWhitespace || $0 == "/" }.map(String.init).filter { $0 != "~" && $0 != "." }
    }

    var isEmpty: Bool { words.isEmpty }

    func matchers() -> [FuzzyMatcher] {
        words.map(FuzzyMatcher.init(query:))
    }
}
