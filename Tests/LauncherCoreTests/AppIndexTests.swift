import Foundation
import LauncherCore
import Testing

private func app(_ name: String, file: String? = nil) -> AppItem {
    AppItem(name: name, url: URL(filePath: "/Applications/\(file ?? name).app"))
}

private func names(_ index: AppIndex, _ query: String, limit: Int = 50) -> [String] {
    index.search(query, limit: limit).map { index.apps[$0].name }
}

struct AppIndexTests {
    @Test func ranksBestMatchFirstThenShorterNames() {
        let index = AppIndex(
            apps: ["Mailplane", "Messages", "Mail", "Maps", "Xcode", "Visual Studio Code"].map { app($0) })
        #expect(names(index, "mail") == ["Mail", "Mailplane"])
        #expect(names(index, "code") == ["Visual Studio Code", "Xcode"])
    }

    @Test func breaksTiesAlphabetically() {
        let index = AppIndex(apps: ["Notes", "Nodes"].map { app($0) })
        #expect(names(index, "no") == ["Nodes", "Notes"])
    }

    @Test func emptyQueryMatchesNothing() {
        let index = AppIndex(apps: [app("Safari")])
        #expect(index.search("", limit: 10).isEmpty)
        #expect(index.search(" ", limit: 10).isEmpty)
    }

    @Test func respectsTheLimit() {
        let index = AppIndex(apps: (1...20).map { app("App \($0)") })
        #expect(index.search("app", limit: 5).count == 5)
    }

    @Test func findsLocalizedAppsByTheirFileName() {
        let index = AppIndex(apps: [app("Calcolatrice", file: "Calculator"), app("Calendario", file: "Calendar")])
        #expect(names(index, "calcu") == ["Calcolatrice"])
        #expect(names(index, "calco") == ["Calcolatrice"])
        #expect(names(index, "calenda") == ["Calendario"])
    }
}
