# Architecture

## Decision log

The source of truth for product and architecture decisions. Rows are numbered and never edited. A later row can
supersede an earlier one.

| # | Date | Decision | Why | By |
|---|---|---|---|---|
| 1 | 2026-11-19 | `FEATURES.md` is the product spec. `launcher` is a temporary codename: bundle ID `dev.edoardo.launcher`, config in `~/.config/launcher/`. | One spec; the rename is a find-and-replace. | Edoardo |
| 2 | 2026-11-19 | Native Swift + AppKit, built as a Swift Package with no Xcode project. macOS 26+, Apple Silicon only. | Speed, and no project file to maintain. | Edoardo |
| 3 | 2026-11-19 | Agent app (`LSUIElement`): no Dock icon, no menu bar icon. App commands live in the launcher. | FEATURES §2, §7. | Edoardo |
| 4 | 2026-11-19 | One non-activating `NSPanel`, built at launch, then only shown and hidden. | Hotkey → visible in one frame; the previous app stays frontmost, which paste-into-app needs later. | Edoardo |
| 5 | 2026-11-19 | ⌘P is the global launcher hotkey everywhere, with no per-app pass-through (it takes over Print). | FEATURES §3. | Edoardo |
| 6 | 2026-11-19 | Indexes live in memory and search is fuzzy. Nothing touches disk or network while typing. | FEATURES §1. | Edoardo |
| 7 | 2026-11-19 | Minimal dependencies: system frameworks first. A third-party library has to clearly beat a little code of our own. | Speed, size, nothing to keep updated. | Edoardo |
| 8 | 2026-11-19 | Milestone 1 is the launcher. Clipboard and calculator come in later milestones. | Scope. | Edoardo |
| 9 | 2026-11-19 | Speed and efficiency come before looks: a plain panel that is excellent on latency, memory, threads and energy. Styling comes later. The rules are in `AGENTS.md` (Performance). | It's a small app, so it has to be excellent at what it does. | Edoardo |

## Principles

- **Performance rules live in `AGENTS.md`.** That covers threads, idling, preparing ahead of time, hot paths, memory,
  drawing and measuring.
- **Pure logic is separate from AppKit.** `LauncherCore` never imports AppKit, and it's tested against the real file
  system, without mocks.
- **The main actor owns all state.** Workers compute and hand back values; nothing is shared, so nothing is locked.

## System overview

```
Sources/
  LauncherCore/            pure Swift, no AppKit, unit-tested
    SearchKey.swift        text → lowercased, diacritic-folded UTF-8 + per-byte bonus + 64-bit byte mask
    FuzzyMatcher.swift     query × SearchKey → score (fzf v2-style dynamic programming)
    AppIndex.swift         AppItem list + keys; search(query, limit) → ranked indices
    AppScanner.swift       walks the app folders → [AppItem]
    DirectoryWatcher.swift FSEvents → callback with the changed folders
  Launcher/                the AppKit app, main actor by default
    main.swift             NSApplication with the accessory policy
    AppDelegate.swift      wiring: panel, ⌘P, index (re)builds; Log (incl. latency logging)
    Background.swift       runInBackground: blocking work on a GCD worker, awaited from the main actor
    HotKeyCenter.swift     global hotkeys via Carbon RegisterEventHotKey, with the press timestamp
    LauncherPanel.swift    the NSPanel: show/hide, key routing, Layout constants
    LauncherViewController.swift  search field + NSTableView, keyboard commands, opening apps
    IconStore.swift        app icons pre-rendered to exact-size bitmaps, in parallel, off the main thread
    ResultViews.swift      fixed-frame cell, bitmap IconView, row view
Support/Info.plist         bundle metadata (bundle ID, LSUIElement), copied in by `make app`
```

**Startup.** `AppDelegate` builds and draws the panel, registers ⌘P, then scans the app folders on a worker. The new
`AppIndex` goes to the view controller, which has `IconStore` render the icons it doesn't have yet. An FSEvents stream
on the app folders triggers a rescan, unless the change is inside a bundle (app updates, caches). The newest rescan
always wins.

**⌘P.** The Carbon handler runs on the main thread with the key press's timestamp. The panel is moved to the screen
under the mouse pointer and made key without activating the app. The time from the key press to the panel being drawn
goes to the `perf` log.

**Typing.** Each keystroke runs `AppIndex.search` synchronously on the main thread (microseconds). The table reloads
only when the matches changed, and its rows show icons already rendered as bitmaps. The time from the keyDown to the
results being drawn goes to the `perf` log.

**Keys.** The field editor turns ↑ ↓ ⏎ ⎋ into commands (`moveUp:`, `insertNewline:` …), and the panel reroutes ⌃K and
⌃J into the same commands. One delegate method handles them all, so an input method that is composing text keeps its
keys. ⌘X/C/V/A/Z are routed by hand, because an agent app has no main menu to do it.

**Opening.** ⏎ or a double click hides the panel and calls `NSWorkspace.openApplication`, which launches the app or
brings it to the front if it's already running. Losing focus also hides the panel. Every hide empties the field.

### Threads

| Thread | Runs | Never |
|---|---|---|
| Main | Events, the hotkey handler, FSEvents callbacks (cheap filter), search, table updates, applying results | File I/O, icon rendering, waiting on anything |
| GCD worker (`runInBackground`, `.utility`) | The app folder scan, then building the `AppIndex` (~15 ms) | Touching UI or shared state |
| GCD workers (`concurrentPerform`, one per core, `.userInitiated`) | Rendering missing icons in parallel, each into its own slot | Touching UI or shared state |
| Swift cooperative pool | Only awaiting; nothing blocks on it | Blocking calls |

At idle, nothing is scheduled: no timers, no polling. Workers exist only while there is work.

### Matching and ranking

- Text is folded once: diacritics removed (`Café` → `cafe`), lowercased, kept as UTF-8. ASCII names take a fast path
  that never creates a `String`.
- A 64-bit mask of the bytes present rejects most non-matches with one AND. A forward scan then checks that the query
  is a subsequence and narrows the columns the dynamic programming has to cover.
- Scores follow fzf: a match is worth 16, a gap costs 3 plus 1 per extra character. Bonuses go to word starts (10
  after whitespace, 9 after `/,:;|`, 8 after other punctuation), camelCase humps and digits (7), and runs of
  consecutive matches. The first query character's bonus counts double. Leading and trailing text is free.
- Apps match on their localized name and, when it differs, on their file name, so "calcu" finds Calcolatrice.
- Ranking: best score, then shorter name, then alphabetical. Frequency and recency come in milestone step 2.

### Icons

The first draw of an app icon costs ~5 ms on average and ~38 ms at worst (measured over 108 apps), because IconServices
renders the layered icon on demand. Drawing it on the main thread while typing is what made the first build stutter.
Now `IconStore` renders every app's icon once, right after indexing. It works on all cores, into a 56×56 px BGRA bitmap
(28 pt at the screen's scale), and a row only sets that bitmap as its layer's contents. The 108 icons render in about
10 ms when IconServices' cache is warm, and take ~1.4 MB in all. A row whose icon isn't ready yet shows none until the
batch lands. The icons don't yet follow the dark or tinted icon style.

### Measured (this Mac)

| Case | Result | How |
|---|---|---|
| Scan of the 3 app folders (113 apps) | ~12–15 ms, on a worker | `make bench` |
| Search over installed apps | ≤ 0.003 ms per keystroke | `make bench` |
| Search over 100k synthetic names | 0.3–7 ms; 1–2 letter queries are the slow end | `make bench` |
| ⌘P → panel drawn, keystroke → results drawn | to be measured on Edoardo's run | `make logs` |
| Idle memory, CPU, threads | to be measured on Edoardo's run | `make stats` |

## Visual decisions

Speed first and style later (decision 9), so this is the plain, fast version.

| Element | Choice | By |
|---|---|---|
| Panel | Fixed size, 680 × 389 pt: a 56 pt search bar plus 8 rows × 40 pt. It never resizes. | Claude |
| Surface | An opaque window in the system window-background color, with square corners and the system shadow. No glass or blur, so the window server never blends or blurs what's behind. | Claude |
| Position | Centered on the screen under the mouse pointer, which is how "the active screen" is defined. | Claude |
| Type | Search field 22 pt regular with a magnifying glass symbol and a "Search" placeholder. Rows 15 pt with 28 pt icons. | Claude |
| Selection | System inset table style in the accent color, always drawn emphasized (the focus stays in the search field). | Claude |
| Motion | None: the panel appears and disappears without animation. | Claude |

## Libraries

No third-party dependencies.

| Need | Pick | Why |
|---|---|---|
| Global hotkey | Carbon `RegisterEventHotKey` (system) | No dependency and no Accessibility permission. `KeyboardShortcuts` wraps the same API and adds a recorder UI we don't need, since config is TOML. |
| Fuzzy matching | Our own, fzf v2-style (`FuzzyMatcher`, ~150 lines) | Tuned to our byte layout, with no per-item allocation. Swift fuzzy libraries allocate per candidate and score worse on word starts. |
| File-system changes | FSEvents (system) | Coalesced, cheap, no polling. |
| App launching | `NSWorkspace` (system) | Launches or brings to front in one call. |
| Icons | `NSWorkspace.icon(forFile:)` drawn into a CoreGraphics bitmap (system) | Rendered once off the main thread at the exact pixel size; no image library needed. |
| Background work | GCD (`DispatchQueue.global`, `concurrentPerform`) behind `async` | Blocking work stays off both the main thread and Swift's cooperative pool. |
| Logging | `os.Logger` (system) | Debug-level latency logs cost next to nothing unless streamed. |
| Tests | Swift Testing (toolchain) | The current standard over XCTest. |
| Formatting | swift-format (toolchain), configured in `.swift-format` | Ships with Swift, so nothing to install. |

The `FEATURES.md` candidates for later steps, GRDB (clipboard storage) and TOMLKit (config), aren't added yet. Each is
decided when its step starts.
