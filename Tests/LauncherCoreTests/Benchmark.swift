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

    /// The real home folder with the default rules (decision 22).
    @Test func homeFolder() {
        let rules = FileRules(
            roots: [NSHomeDirectory()],
            ignore: IgnoreRules([".*", "~/Library", "node_modules", ".build", "*.photoslibrary"]),
            maxDepth: 6)
        var first = FileIndex()
        let cold = ContinuousClock().measure { FileScanner.scan(rules, into: &first) }
        first = FileIndex()
        var index = FileIndex()
        let before = footprint()
        let scan = ContinuousClock().measure {
            FileScanner.scan(rules, into: &index)
            index.trim()
        }
        print(
            "home folder: \(index.count) entries, first scan \(cold.ms), next \(scan.ms), index \(index.memoryBytes / 1024) KB (footprint +\((footprint() - before) / 1_048_576) MB)"
        )
        report(index, iterations: 50)
    }

    @Test func hundredThousandFiles() {
        var random = SplitMix64(seed: 7)
        let words = ["project", "report", "final", "draft", "invoice", "photo", "notes", "budget", "readme", "main"]
        var index = FileIndex()
        let before = footprint()
        index.addRoot("/Users/me")
        for folder in 0..<500 { index.insert("/Users/me/folder\(folder)", isFolder: true) }
        for number in 0..<100_000 {
            let name = (0..<3).map { _ in words.randomElement(using: &random)! }.joined(separator: "-")
            index.insert("/Users/me/folder\(number % 500)/\(name) \(number).txt", isFolder: false)
        }
        index.trim()
        print(
            "synthetic files: \(index.count), index \(index.memoryBytes / 1024) KB (footprint +\((footprint() - before) / 1_048_576) MB)"
        )
        report(index, iterations: 50)
    }

    private func report(_ index: FileIndex, iterations: Int) {
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

/// The process's memory footprint, as Activity Monitor shows it.
private func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
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
