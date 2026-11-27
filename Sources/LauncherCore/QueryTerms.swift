/// A query split into words, at spaces and at `/`: "budget review" and "acme/deploy" are two words each.
///
/// Every word must match, in any order. For files, the last word must match the name, and the others may match the
/// name or a folder above it, so "acme deploy" finds deploy.sh in ~/Projects/Acme, while "acme" alone still finds only
/// what's named acme. `~` and `.` are skipped, so a path like `~/Downloads/contr` works too.
///
/// A word like `*.pdf` asks for an extension instead (decision 80): only files with it match, and with nothing else
/// typed they come newest first.
struct QueryTerms {
    /// Every word, as typed.
    let words: [String]
    /// The extensions asked for, lowercased and without `*.`: a file with any of them matches.
    let extensions: [String]
    /// The words that match names: all but the extensions.
    let nameWords: [String]

    init(_ query: String) {
        words = query.split { $0.isWhitespace || $0 == "/" }.map(String.init).filter { $0 != "~" && $0 != "." }
        var extensions: [String] = []
        var nameWords: [String] = []
        for word in words {
            if word.hasPrefix("*."), word.count > 2, !word.dropFirst().contains("*") {
                extensions.append(word.dropFirst(2).lowercased())
            } else {
                nameWords.append(word)
            }
        }
        self.extensions = extensions
        self.nameWords = nameWords
    }

    var isEmpty: Bool { words.isEmpty }

    /// Matchers for the words that match names.
    func matchers() -> [FuzzyMatcher] {
        nameWords.map(FuzzyMatcher.init(query:))
    }
}
