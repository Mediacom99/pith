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

## Principles

- **Work happens before the keystroke.** Scanning, folding and per-item bonuses are computed at index time. Per
  keystroke we only compare bytes.
- **Nothing in a hot path allocates per item.** The matcher reuses one scratch buffer; each search allocates only its
  result arrays.
- **Pure logic is separate from AppKit.** `LauncherCore` never imports AppKit, and it's tested against the real file
  system, without mocks.
- **The main actor is the default.** The app target is main-actor isolated. Scanning runs on a detached task, and
  results come back to the main actor.
- **Performance gets measured in Release** (`make bench`, `make app`).

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
    AppDelegate.swift      wiring: panel, ⌘P, index (re)builds
    HotKeyCenter.swift     global hotkeys via Carbon RegisterEventHotKey
    LauncherPanel.swift    the NSPanel: show/hide, collapse/expand, key routing, Layout constants
    LauncherViewController.swift  search field + NSTableView, keyboard commands, opening apps
    ResultViews.swift      reusable cell and row views, icon cache
Support/Info.plist         bundle metadata (bundle ID, LSUIElement), copied in by `make app`
```

**Startup.** `AppDelegate` builds the panel and its view hierarchy, registers ⌘P, then scans the app folders on a
detached task. The resulting `AppIndex` is handed to the view controller. An FSEvents stream on the same folders
triggers a rescan, unless the change is inside a bundle (app updates, caches). The newest rescan always wins.

**⌘P.** The Carbon handler runs on the main thread and toggles the panel. To show it, the panel is placed on the
screen under the mouse pointer and made key without activating the app.

**Typing.** Each keystroke runs `AppIndex.search` synchronously on the main thread. The view controller reloads the
table and selects the first row. The panel grows to its full height when there are results and shrinks back to the
search bar when there are none. Its top edge never moves.

**Keys.** The field editor turns ↑ ↓ ⏎ ⎋ into commands (`moveUp:`, `insertNewline:` …), and the panel reroutes ⌃K and
⌃J into the same commands. One delegate method handles them all, so an input method that is composing text keeps its
keys. ⌘X/C/V/A/Z are routed by hand, because an agent app has no main menu to do it.

**Opening.** ⏎ or a double click hides the panel and calls `NSWorkspace.openApplication`, which launches the app or
brings it to the front if it's already running. Losing focus also hides the panel. Every hide empties the field.

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

### Measured (`make bench`, Release, this Mac)

| Case | Result |
|---|---|
| Scan of the 3 app folders (113 apps) | ~12–15 ms, off the main thread |
| Search over installed apps | ≤ 0.003 ms per keystroke |
| Search over 100k synthetic names | 0.3–7 ms; 1–2 letter queries are the slow end |

## Visual decisions

| Element | Choice | By |
|---|---|---|
| Panel | 680 pt wide. A 56 pt search bar that grows to 8 rows × 40 pt (plus 6 pt insets) when there are results. The top edge stays fixed. | Claude |
| Position | Centered on the screen under the mouse pointer, which is how "the active screen" is defined. The expanded panel is centered, and the bar is its top edge. | Claude |
| Material | `NSGlassEffectView` (Liquid Glass) with a 20 pt corner radius. Light and dark follow the system. | Claude |
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
| App launching, icons | `NSWorkspace` (system) | Launches or brings to front in one call. Icons are cached in `NSCache`. |
| Logging | `os.Logger` (system) | |
| Tests | Swift Testing (toolchain) | The current standard over XCTest. |
| Formatting | swift-format (toolchain), configured in `.swift-format` | Ships with Swift, so nothing to install. |

The `FEATURES.md` candidates for later steps, GRDB (clipboard storage) and TOMLKit (config), aren't added yet. Each is
decided when its step starts.
