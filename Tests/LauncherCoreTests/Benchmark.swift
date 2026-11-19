import Foundation
import LauncherCore
import Testing

/// Timings, not assertions: run with `make bench` (release build). `make test` skips this suite.
@Suite(.serialized) struct Benchmark {
    private static let queries = ["s", "sa", "saf", "term", "vsc", "sys set", "qqq"]

    @Test func installedApps() {
        var apps: [Item] = []
        let scan = ContinuousClock().measure {
            apps = AppScanner.scan(AppScanner.defaultRoots, extras: AppScanner.defaultExtras)
        }
        var index = SearchIndex.empty
        let build = ContinuousClock().measure { index = SearchIndex(items: apps) }
        print("installed apps: \(apps.count), scan \(scan.ms), index \(build.ms)")
        report(index, iterations: 2_000)
    }

    /// A stand-in for the file index to come: 100k names built from a fixed vocabulary.
    @Test func hundredThousandNames() {
        var random = SplitMix64(seed: 42)
        let words = [
            "project", "report", "final", "draft", "invoice", "photo", "screen", "shot", "notes", "budget",
            "design", "spec", "meeting", "backup", "archive", "readme", "config", "index", "main", "test",
            "Résumé", "Präsentation", "système", "Q3", "2026", "v2",
        ]
        let separators = [" ", "-", "_", ""]
        let extensions = [".pdf", ".md", ".swift", ".png", ".txt", ""]
        let apps = (0..<100_000).map { _ in
            let count = Int.random(in: 2...4, using: &random)
            let name =
                (0..<count).map { _ in words.randomElement(using: &random)! }
                .joined(separator: separators.randomElement(using: &random)!)
                + extensions.randomElement(using: &random)!
            return Item(name: name, appAt: URL(filePath: "/x/\(name).app"))
        }
        var index = SearchIndex.empty
        let build = ContinuousClock().measure { index = SearchIndex(items: apps) }
        print("synthetic names: \(apps.count), index \(build.ms)")
        report(index, iterations: 10)
    }

    private func report(_ index: SearchIndex, iterations: Int) {
        for query in Self.queries {
            var matches = 0
            let elapsed = ContinuousClock().measure {
                for _ in 0..<iterations { matches = index.search(query, limit: 50).count }
            }
            print(
                "  \(query.padding(toLength: 8, withPad: " ", startingAt: 0)) \((elapsed / iterations).ms) per search, \(matches) shown"
            )
        }
    }
}

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension Duration {
    fileprivate var ms: String {
        let (seconds, attoseconds) = components
        return String(format: "%.3f ms", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
    }
}
