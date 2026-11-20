import AppKit
import LauncherCore
import Testing

@testable import Launcher

/// The keystroke path in a real (never shown) panel over the installed apps, split into update and draw.
/// Timings, not assertions: run with `make bench`.
@Suite(.serialized) struct UIBenchmark {
    private static let typing = [
        "s", "sa", "saf", "safa", "", "g", "gh", "gho", "", "t", "te", "ter", "term", "", "v", "vs", "vsc", "",
    ]

    @Test func keystrokes() async {
        let items = AppScanner.scan(AppScanner.defaultRoots, extras: AppScanner.defaultExtras)
        // The real home folder with the default rules, as the app indexes it.
        let files = FileSearchEngine()
        await files.rebuild(Config().fileRules())
        let panel = makePanel(items: items + Command.allCases.map(Item.init(command:)), files: files)
        let bitmap = panel.contentView!.bitmapImageRepForCachingDisplay(in: panel.contentView!.bounds)!
        let clock = ContinuousClock()
        var update = Duration.zero
        var draw = Duration.zero
        var render = Duration.zero
        let rounds = Int(ProcessInfo.processInfo.environment["UI_BENCH_ROUNDS"] ?? "20")!
        for round in 0...rounds {
            for query in Self.typing {
                let start = clock.now
                await type(query, in: panel)
                let updated = clock.now
                panel.displayIfNeeded()
                let drawn = clock.now
                // Forces every view to actually draw, as the screen would.
                panel.contentView!.cacheDisplay(in: panel.contentView!.bounds, to: bitmap)
                let rendered = clock.now
                guard round > 0 else { continue }  // round 0 warms up the cell views
                update += updated - start
                draw += drawn - updated
                render += rendered - drawn
            }
        }
        let count = rounds * Self.typing.count
        print("apps \(items.count), files \(await files.count)")
        print(
            "per keystroke: update \((update / count).ms), displayIfNeeded \((draw / count).ms), full render \((render / count).ms)"
        )
    }
}

extension UIBenchmark {
    /// What ⌘P does in-process before the window server: sync running apps, fill the empty state, lay out, draw.
    @Test(arguments: [Config.EmptyState.recent, .running, .none])
    func show(emptyState: Config.EmptyState) {
        let items = AppScanner.scan(AppScanner.defaultRoots, extras: AppScanner.defaultExtras)
        let panel = makePanel(items: items, opened: items.prefix(8).map(\.id), emptyState: emptyState)
        let clock = ContinuousClock()
        var total = Duration.zero
        var rows = 0
        let rounds = 50
        for round in 0...rounds {
            let start = clock.now
            panel.launcher.prepareToShow()
            panel.displayIfNeeded()
            if round > 0 { total += clock.now - start }
            rows = panel.launcher.rows.count
            panel.launcher.reset()
        }
        print("show (\(emptyState), \(rows) rows): \((total / rounds).ms)")
    }
}

extension Duration {
    fileprivate var ms: String {
        let (seconds, attoseconds) = components
        return String(format: "%.3f ms", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
    }
}

extension UIBenchmark {
    @Test func fileSearchRoundTrip() async {
        let files = FileSearchEngine()
        await files.rebuild(Config().fileRules())
        let clock = ContinuousClock()
        var generation = 0
        for query in ["s", "sa", "saf", "g", "gh", "term", "vsc"] {
            var total = Duration.zero
            for _ in 0..<50 {
                generation += 1
                let start = clock.now
                _ = await files.search(query, limit: 50, generation: generation)
                total += clock.now - start
            }
            print("file search round trip \(query): \((total / 50).ms)")
        }
    }
}
