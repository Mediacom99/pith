import LauncherCore
import Testing

private func score(_ query: String, _ text: String) -> Int32? {
    var matcher = FuzzyMatcher(query: query)
    return matcher.score(SearchKey(text))
}

struct FuzzyMatcherTests {
    @Test func matchesSubsequencesOnly() {
        #expect(score("sfr", "Safari") != nil)
        #expect(score("safari", "Safari") != nil)
        #expect(score("rfs", "Safari") == nil)
        #expect(score("safarix", "Safari") == nil)
    }

    @Test func emptyQueryMatchesNothing() {
        #expect(score("", "Safari") == nil)
        #expect(score("   ", "Safari") == nil)
    }

    @Test func ignoresCaseAndDiacritics() {
        #expect(score("SAFARI", "safari") == score("safari", "Safari"))
        #expect(score("cafe", "Café Menu") != nil)
        #expect(score("über", "Uber Eats") != nil)
        #expect(score("e", "É") != nil)
    }

    @Test func matchesNonLatinText() {
        #expect(score("メモ", "メモ帳") != nil)
        #expect(score("帳メ", "メモ帳") == nil)
    }

    @Test func prefersWordStarts() throws {
        let acronym = try #require(score("ss", "System Settings"))
        let midWord = try #require(score("ss", "Messages"))
        #expect(acronym > midWord)

        let wordStart = try #require(score("code", "Visual Studio Code"))
        let insideWord = try #require(score("code", "Xcode"))
        #expect(wordStart > insideWord)
    }

    @Test func prefersCamelCaseHumps() throws {
        #expect(try #require(score("fb", "FaceBook")) > #require(score("fb", "Fabulous")))
    }

    @Test func prefersConsecutiveCharacters() throws {
        #expect(try #require(score("term", "Terminal")) > #require(score("term", "Tea Room")))
    }

    @Test func leadingAndTrailingTextIsFree() {
        #expect(score("mail", "Mail") == score("mail", "Mail Merge"))
        #expect(score("mail", "Mail") == score("mail", "The Mail"))
    }
}
