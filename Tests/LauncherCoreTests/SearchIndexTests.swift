import Foundation
import LauncherCore
import Testing

private func app(_ name: String, file: String? = nil) -> Item {
    Item(name: name, appAt: URL(filePath: "/Applications/\(file ?? name).app"))
}

private func names(_ index: SearchIndex, _ query: String, limit: Int = 50, boosts: [Int32] = []) -> [String] {
    index.search(query, limit: limit, boosts: boosts).map { index.items[$0].name }
}

struct SearchIndexTests {
    @Test func ranksBestMatchFirstThenShorterNames() {
        let index = SearchIndex(
            items: ["Mailplane", "Messages", "Mail", "Maps", "Xcode", "Visual Studio Code"].map { app($0) })
        #expect(names(index, "mail") == ["Mail", "Mailplane"])
        #expect(names(index, "code") == ["Visual Studio Code", "Xcode"])
    }

    @Test func breaksTiesAlphabetically() {
        let index = SearchIndex(items: ["Notes", "Nodes"].map { app($0) })
        #expect(names(index, "no") == ["Nodes", "Notes"])
    }

    @Test func emptyQueryMatchesNothing() {
        let index = SearchIndex(items: [app("Safari")])
        #expect(index.search("", limit: 10).isEmpty)
        #expect(index.search(" ", limit: 10).isEmpty)
    }

    @Test func respectsTheLimit() {
        let index = SearchIndex(items: (1...20).map { app("App \($0)") })
        #expect(index.search("app", limit: 5).count == 5)
    }

    @Test func findsLocalizedAppsByTheirFileName() {
        let index = SearchIndex(items: [app("Calcolatrice", file: "Calculator"), app("Calendario", file: "Calendar")])
        #expect(names(index, "calcu") == ["Calcolatrice"])
        #expect(names(index, "calco") == ["Calcolatrice"])
        #expect(names(index, "calenda") == ["Calendario"])
    }

    @Test func findsCommands() {
        let index = SearchIndex(items: Command.allCases.map(Item.init(command:)) + [app("Safari")])
        #expect(names(index, "quit") == ["Quit Launcher"])
        #expect(names(index, "config") == ["Open Config", "Reload Config"])
    }

    @Test func boostsReorderCloseMatches() {
        let index = SearchIndex(items: ["Safari", "Slack", "Spotify"].map { app($0) })
        #expect(names(index, "s").first == "Slack", "without history: shortest name first")
        var boosts = [Int32](repeating: 0, count: 3)
        boosts[index.position(of: "/Applications/Spotify.app")!] = 20
        #expect(names(index, "s", boosts: boosts).first == "Spotify")
    }

    @Test func findsItemsById() {
        let index = SearchIndex(items: [app("Safari"), Item(command: .quit)])
        #expect(index.position(of: "command:quit").map { index.items[$0].name } == "Quit Launcher")
        #expect(index.position(of: "/Applications/Safari.app").map { index.items[$0].name } == "Safari")
        #expect(index.position(of: "/nope") == nil)
    }
}
