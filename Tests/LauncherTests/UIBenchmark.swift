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

    @Test func keystrokes() {
        let panel = makePanel(apps: AppScanner.scan(AppScanner.defaultRoots))
        let bitmap = panel.contentView!.bitmapImageRepForCachingDisplay(in: panel.contentView!.bounds)!
        let clock = ContinuousClock()
        var update = Duration.zero
        var draw = Duration.zero
        var render = Duration.zero
        let rounds = 20
        for round in 0...rounds {
            for query in Self.typing {
                let start = clock.now
                type(query, in: panel)
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
        print(
            "per keystroke: update \((update / count).ms), displayIfNeeded \((draw / count).ms), full render \((render / count).ms)"
        )
    }
}

extension Duration {
    fileprivate var ms: String {
        let (seconds, attoseconds) = components
        return String(format: "%.3f ms", Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
    }
}
