import AppKit
import LauncherCore
import TestSupport
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

extension UIBenchmark {
    /// What ⌘⇧V does in-process with a month of history (step 8): 5,000 clips, among them 300 screenshots. Loading
    /// it at launch, then filling the rows and the preview, laying out, drawing. Then typing in the clipboard, update
    /// and draw.
    @Test func showClipboard() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PithBench-clipboard-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        var clips: [(content: ClipContent, source: String?, minutesAgo: Double)] = []
        for number in 0..<5_000 {
            let minutesAgo = Double(5_000 - number) * 8
            if number % 16 == 7 {
                // A screenshot: each a different size, so none is a copy of another.
                let png = try flatPNG(width: 2_880 - number / 16, height: 1_800)
                clips.append((ClipContent(kind: .image, text: "", items: [], image: png), nil, minutesAgo))
                continue
            }
            let body =
                "docker compose -f deploy/acme-\(number).yml up --build\nservices:\n  web:\n    image: acme/site:\(number)\n"
            clips.append((text(body), number % 3 == 0 ? "com.apple.Terminal" : nil, minutesAgo))
        }
        let panel = try await clipboardPanel(folder, clips)
        let files = FileManager.default
        let onDisk = try files.subpathsOfDirectory(atPath: folder.path).reduce(0) { total, path in
            let size = try? files.attributesOfItem(atPath: folder.appending(path: path).path)[.size]
            return total + (size as? Int ?? 0)
        }
        let launch = ContinuousClock()
        let loadStart = launch.now
        let reloaded = ClipboardHistory(store: ClipboardStore(folder: folder))
        await reloaded.load()
        print(
            "clipboard at launch (\(reloaded.index.count) clips, \(onDisk / 1_000_000) MB on disk): load \((launch.now - loadStart).ms)"
        )
        let clock = ContinuousClock()
        var total = Duration.zero
        let rounds = 50
        for round in 0...rounds {
            let start = clock.now
            panel.launcher.prepareToShow(.clipboard)
            panel.displayIfNeeded()
            if round > 0 { total += clock.now - start }
            panel.launcher.reset()
        }
        print("show clipboard (\(clips.count) clips): \((total / rounds).ms)")

        panel.launcher.prepareToShow(.clipboard)
        var update = Duration.zero
        var draw = Duration.zero
        let typing = ["d", "do", "doc", "dock", "docker", "", "a", "ac", "acme", "acme-4", "acme-42", ""]
        for round in 0...10 {
            for query in typing {
                let start = clock.now
                await type(query, in: panel)
                let updated = clock.now
                panel.displayIfNeeded()
                guard round > 0 else { continue }
                update += updated - start
                draw += clock.now - updated
            }
        }
        let count = 10 * typing.count
        print("clipboard keystroke: update \((update / count).ms), draw \((draw / count).ms)")
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
