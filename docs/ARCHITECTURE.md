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
| 10 | 2026-11-19 | Milestone 1 holds features 6, 7, 8, 9, 10, 16, 17 and 18 (as numbered in the chat): learned ranking, running indicator, ⌘K app actions, Finder, icon style, config file, launcher commands, launch at login. It also holds a configurable empty state. Files and folders move to a later milestone. | Scope. | Edoardo |
| 11 | 2026-11-19 | What the launcher shows before you type is set in the config: `recent`, `running` or `none`. This supersedes FEATURES §4 "Empty state: nothing". | Opening on something useful. | Edoardo |
| 12 | 2026-11-19 | `recent` lists the items you opened from the launcher, newest first, and ⏎ opens one again. It shares its history with the learned ranking. `recent` is the default. | Recommended option. | Edoardo |
| 13 | 2026-11-19 | `running` lists open apps, most recently used first (like ⌘Tab). | Recommended option; ⌘P ⏎ switches back. | Edoardo |
| 14 | 2026-11-19 | Launch at login is on by default, but only a copy running from an Applications folder registers itself. Dev builds in `.build` never do. | No stray login items from dev builds. | Edoardo |
| 15 | 2026-11-19 | Which app opens each file type is set in config.toml under `[open_with]` (extension or type → app). It applies only to files opened from the launcher; macOS defaults stay untouched. It ships with file search (features 11–15, a later milestone). | The launcher shouldn't change system settings. | Edoardo |
| 16 | 2026-11-19 | Links get the same treatment: `[open_links]` maps URL schemes (`https`, `mailto`…) to apps, for links the launcher opens, such as the clipboard's Open URL. | Consistency with decision 15. | Edoardo |
| 17 | 2026-11-19 | The `running` empty state continues past the open apps with every other app, alphabetically (no duplicates, no commands), so scrolling down browses all apps. | Requested. | Edoardo |
| 18 | 2026-11-19 | Milestone 2 is files and folders: features 11–15 (search, file actions, Quick Look, folder actions, Zip). | Scope. | Edoardo |
| 19 | 2026-11-19 | Apps and files share one ranked list (match quality plus history), with a head start for apps. | "saf" should give Safari before safari-notes.md; a clearly better or habitual file can still win. | Edoardo |
| 20 | 2026-11-19 | Quick Look opens with ⌘Y always, and with Space only when the search field is empty. | Space must stay a space in queries. | Edoardo |
| 21 | 2026-11-19 | A finished Zip posts a macOS notification (permission asked once); clicking it reveals the zip. | Feedback without popping windows. | Edoardo |
| 22 | 2026-11-19 | With no `folders` in config.toml, the file index covers the whole home folder, minus ~/Library, hidden files and the ignore list. | Find anything by default. | Edoardo |

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
    Item.swift             Item (an app, file, folder or Command) with a stable id; Command (Open/Reload Config, Quit)
    SearchKey.swift        text → lowercased, diacritic-folded UTF-8 + per-byte bonus + 64-bit byte mask
    KeyStore.swift         many search keys in four flat buffers (for the file index)
    FuzzyMatcher.swift     query × key → score (fzf v2-style dynamic programming)
    SearchIndex.swift      apps and commands + keys + id lookup; scored search with boosts
    FileIndex.swift        files and folders as a tree in flat arrays, O(1) path lookup, parallel top-k search
    FileScanner.swift      fts walk of the configured folders; IgnoreRules; FileRules
    FileSearchEngine.swift owns the FileIndex on a serial queue: rebuilds, FSEvents patches, searches
    History.swift          what was opened and when: recent list, frecency, boosts for apps and files
    AppScanner.swift       walks the app folders (+ Finder) → [Item] with resolved-path ids
    DirectoryWatcher.swift FSEvents → folders or per-file events with flags, with source-level exclusions
    Config.swift           config.toml settings, defaults, problems with line numbers, the commented template
    TOMLReader.swift       a small strict TOML reader (the subset the config needs)
    Hotkey.swift           "cmd+shift+p" → Carbon key code + modifiers
  Launcher/                the AppKit app, main actor by default
    main.swift             NSApplication with the accessory policy
    AppDelegate.swift      wiring: panel, config → hotkey/empty state/login item, commands, index (re)builds; Log
    Background.swift       runInBackground: blocking work on a GCD worker, awaited from the main actor
    ConfigStore.swift      ~/.config/launcher/config.toml: create, read and parse on a worker, reload on change, open
    HistoryStore.swift     the History, loaded and saved as JSON on workers
    RunningApps.swift      open apps in MRU order: runningApplications re-read on launch/quit and on show
    LoginItem.swift        SMAppService registration, for a copy in an Applications folder only
    HotKeyCenter.swift     global hotkeys via Carbon RegisterEventHotKey, registered and replaced at runtime
    LauncherPanel.swift    the NSPanel: show/hide, collapse/expand, key routing (⌃K/⌃J, ⌘K), the search field's editor
    LauncherViewController.swift  rows, merged app + file search, empty state, ⌘K sublists, keyboard, opening
    Actions.swift          ⌘K actions per kind, the SF Symbols rows use, AppResolver (config app names, Open With…)
    IconStore.swift        app, symbol and file-type icons as exact-size bitmaps rendered off the main thread
    ResultViews.swift      fixed-frame cell (title, folder detail, running dot), bitmap IconView, row view
Support/Info.plist         bundle metadata (bundle ID, LSUIElement), copied in by `make app`
```

Files the app keeps:

| File | What | Written |
|---|---|---|
| `~/.config/launcher/config.toml` | Settings (FEATURES §8) | Created with commented defaults on first launch; then only by you |
| `~/Library/Application Support/launcher/history.json` | What you opened and when (≤ 200 items × 10 times); deleted files are dropped | After every open or deletion, on a serial worker, atomically |

**Startup.** `AppDelegate` builds and draws the panel, loads the history, then the config, and registers the
configured hotkey. The app folders and Finder are scanned on a worker, and the launcher's commands are added, minus
the launcher itself. The new `SearchIndex` goes to the view controller, which has `IconStore` render the icons it
doesn't have yet. FSEvents streams trigger a rescan when the app folders change (unless the change is inside a bundle)
and a reload when the config's folder changes. The newest rescan or reload always wins.

**Config.** A bad setting keeps its default and becomes a problem with its line number. Problems are listed first in
the empty state, and ⏎ on one opens the file. A changed hotkey is registered before the old one is let go, so if the
new one is taken, the old one keeps working. Launch at login registers or unregisters only when the setting changes,
and only for a copy in an Applications folder.

**⌘P.** The Carbon handler runs on the main thread with the key press's timestamp. The view controller fills in the
empty state first, so the panel appears at its final size. The panel is then moved to the screen under the mouse
pointer and made key without activating the app. The time from the key press to the panel being drawn goes to the
`perf` log.

**Empty state.** `recent` lists the latest opens from the history that are still in the index, up to 8. `running`
lists open apps in most-recently-used order, including apps outside the indexed folders, then every other indexed
app alphabetically. As with ⌘Tab, the first one is the app you were in and the second is selected. `none` lists nothing.

**Typing.** Each keystroke runs `SearchIndex.search` synchronously on the main thread (microseconds). The match score
is boosted by the history: frecency, counting opens weighted by age (Firefox-style buckets), turns into up to +48
points on a log scale. The table reloads only when the rows changed, and its rows show bitmaps that are already
rendered. The panel is just the search bar while there's nothing to list, so it resizes only on that change. The
search field has its own field editor with inline predictions, Writing Tools, autocompletion, spell and grammar
checking, substitutions and data detection switched off: they all run on every keystroke and none belong in a search
box. The keystroke latency goes to the `perf` log, split into delivery (key press → our handler), update and draw.

**Keys.** The field editor turns ↑ ↓ ⏎ ⎋ into commands (`moveUp:`, `insertNewline:` …), and the panel reroutes ⌃K and
⌃J into the same commands. One delegate method handles them all, so an input method that is composing text keeps its
keys. ⌘X/C/V/A/Z are routed by hand, because an agent app has no main menu to do it.

**⌘K.** On an app row, ⌘K replaces the list with its actions: Open and Reveal in Finder, plus Quit and Force Quit if
it's running. The search field filters them, ⏎ runs one, and ⎋ or ⌘K goes back to the search and selection you had.

**Opening.** ⏎ or a double click records the item in the history, hides the panel, then launches the app (or brings
it to the front) or runs the command. Losing focus also hides the panel. Every hide empties the field.

### Threads

| Thread | Runs | Never |
|---|---|---|
| Main | Events, the hotkey handler, NSWorkspace callbacks, the app search, merging results, table updates, applying results | File I/O, icon rendering, IPC, waiting on anything (the one exception: resolving a newly launched app's bundle path, once per process) |
| Serial GCD queue `launcher.files` (`.userInitiated`) | Owns the file index: searches (spread over the cores with `concurrentPerform`), FSEvents patches (one `lstat` each), subtree rescans | Touching UI |
| GCD worker (`runInBackground` or `global`) | Full file scans (`.utility`); the app scan and index build; config reading, parsing and app resolution; loading the history; opening files; Reveal, Copy, Trash; Open With… choices; login item registration | Touching UI or shared state |
| GCD workers (`concurrentPerform`, one per core, `.userInitiated`) | Rendering missing icons in parallel, each into its own slot | Touching UI or shared state |
| Serial GCD queue `launcher.history` (`.utility`) | Saving the history, in order; quitting waits for it | Touching UI or shared state |
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
- Ranking: match score plus the history boost, then shorter name, then alphabetical. The boost is
  `min(48, 12 · log2(1 + frecency / 100))`: one open today is worth +12, a daily habit tops out at +48 (about three
  well-placed characters), so habits reorder close matches without burying a clearly better one.

### Icons

The first draw of an app icon costs ~5 ms on average and ~38 ms at worst (measured over 108 apps), because IconServices
renders the layered icon on demand. Drawing it on the main thread while typing is what made the first build stutter.
Now `IconStore` renders every app's icon once, right after indexing. It works on all cores, into a 56×56 px BGRA bitmap
(28 pt at the screen's scale), and a row only sets that bitmap as its layer's contents. The 108 icons render in about
10 ms when IconServices' cache is warm, and take ~1.4 MB in all. A row whose icon isn't ready yet shows none until the
batch lands. Commands, actions and problems use SF Symbols, rendered the same way in the secondary label color.

Rendering happens under the app's current appearance (light or dark). Everything is re-rendered when that changes
(KVO on `NSApp.effectiveAppearance`) or when the system icon style changes (Default, Dark, Clear, Tinted). For the
style there's no public API, so we listen for AppKit's private `NSWorkspaceIconAppearanceConfigurationDidChangeNotification`,
found in the system's shared cache next to the `AppleIconAppearanceTheme` preference. If that notification ever stops
being posted, icons still update on the next appearance change. Under the Default style, light and dark renders are
identical.

### Measured (this Mac)

| Case | Result | How |
|---|---|---|
| Scan of the 3 app folders (113 apps) | ~12–15 ms, on a worker | `make bench` |
| Search over installed apps | ≤ 0.003 ms per keystroke | `make bench` |
| Scan of the home folder with the default rules (35,627 entries) | 130–150 ms on a worker (warm cache) | `make bench` |
| File index memory | 4.4 MB for the home folder; 16 MB for 100k files | `make bench` (`FileIndex.memoryBytes`) |
| File search | 0.1–0.3 ms (35k or 100k entries, over the cores); round trip from the main thread 0.1–0.2 ms | `make bench` |
| Keystroke work in-process (apps + 35.6k files, merge, update the rows, render; offscreen) | ~1.5 ms | `make bench` (UIBenchmark) |
| ⌘P work in-process (sync running apps, fill the empty state, lay out, draw; offscreen) | 0.3 ms recent (8 rows), 0.4 ms running (114 rows), 0.1 ms none | `make bench` (UIBenchmark) |
| FSEvents → file searchable | about 0.5–1 s (0.5 s coalescing) | tests |
| ⌘P → panel drawn, on screen | 5–8 ms; 39 ms the first time after launch | `make logs` |
| Keystroke → results drawn, on screen | 4–32 ms, typically 6–13 ms, before text services were switched off | `make logs` |
| Idle | 24 MB footprint, 0% CPU, 6 threads | `make stats` |

## Visual decisions

Speed first and style later (decision 9), so this is the plain, fast version.

| Element | Choice | By |
|---|---|---|
| Panel | 680 pt wide. Only the 56 pt search bar when there are no results (FEATURES §4); 389 pt, with 8 rows × 40 pt, when there are. The top edge stays fixed. | Claude |
| Surface | An opaque window in the system window-background color, with square corners and the system shadow. No glass or blur, so the window server never blends or blurs what's behind. | Claude |
| Position | On the screen under the mouse pointer, which is how "the active screen" is defined. The expanded panel would be centered, and the search bar is its top edge. | Claude |
| Type | Search field 22 pt regular with a magnifying glass symbol and a "Search" placeholder. Rows 15 pt with 28 pt icons. | Claude |
| Selection | System inset table style in the accent color, always drawn emphasized (the focus stays in the search field). | Claude |
| Running indicator | A 4 pt dot in the secondary label color under the icon, like the Dock. | Claude |
| File rows | The name, then its folder (`~/…`) in 12 pt secondary text, cut from the start when long; the name gets up to two thirds of the row. Icons by type: one for folders, one per extension, an app's own. | Claude |
| Commands, actions, problems | SF Symbols in the secondary label color in place of an icon: gearshape, arrow.clockwise, power for commands; arrow.up.forward.app, folder, link, square.grid.2x2, terminal, doc.on.doc, trash, xmark.circle, xmark.octagon for actions; exclamationmark.triangle for problems. A problem row reads "Config problem, line N: …". | Claude |
| ⌘K | Sublists replace the list in place: "Actions for <item>", then "Open <file> with…". ⎋ steps back one level as it was; ⌘K goes back to the search. | Claude |
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
| Config format | Our own strict TOML subset reader (`TOMLReader`, ~250 lines) | The config needs tables, strings, booleans and arrays. TOMLKit wraps a C++ library (toml++), a large dependency for a few keys. The reader rejects what it doesn't support with a line number, never guessing. |
| History storage | JSON via `Codable` (system) | ≤ 200 small entries, so SQLite would be overkill. GRDB stays a candidate for the clipboard. |
| Launch at login | `SMAppService.mainApp` (ServiceManagement, system) | The current API; no helper app needed. |
| Running apps | `NSWorkspace` notifications (system) | Launch, activation and quit events, so no polling. |
| File walk | `fts` (libc) with `FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV | FTS_NOSTAT` | As fast as `find`; no stat per file, no symlink following, no crossing into mounts. `FileManager`'s enumerator is slower and allocates a URL per entry. |
| File types | UniformTypeIdentifiers (system) | Package detection, file-type icons, `[open_with]` type matching. |
| Shared state for stale searches | `Atomic` (Synchronization, toolchain) | One relaxed integer, so no lock. |
| Tests | Swift Testing (toolchain) | The current standard over XCTest. |
| Formatting | swift-format (toolchain), configured in `.swift-format` | Ships with Swift, so nothing to install. |

GRDB, the `FEATURES.md` candidate for clipboard storage, is decided when the clipboard milestone starts.
