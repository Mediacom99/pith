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
| 23 | 2026-11-20 | Queries are split into words at spaces and `/`; every word must match, in any order. For files, the last word matches the name and earlier words match the name or a folder above it, at half weight; one word matches names only. | Requested: multi-word queries failed, and paths should work. The rules are Claude's proposal; one word staying names-only keeps a folder name from flooding the results. | Edoardo |
| 24 | 2026-11-20 | The styling that decision 9 put off starts now, through the impeccable skill. It has no macOS platform, so PRODUCT.md sets `ios` and a macOS section overrides the iPhone rules (touch targets, tab bars, simulator). PRODUCT.md and DESIGN.md live in `docs/`. Its screenshots come from `make snapshots`. | `ios` turns on its native checks (VoiceOver, both appearances, system colors) and off its web tooling (CSS rules, browser), which can't read Swift. | Edoardo |
| 25 | 2026-11-20 | Edoardo picks the visual direction, from options Claude offers; Claude picks the exact values (sizes, colors, spacing). This replaces "visual choices are Claude's call". | Edoardo is driving the design now. | Edoardo |
| 26 | 2026-11-20 | The design work has its own plan, `docs/DESIGN-PLAN.md`, alongside the milestones. It covers every surface in `FEATURES.md`, including the calculator and clipboard that aren't built yet. | Requested: the planned surfaces get designed in the same style before they're built. | Edoardo |
| 27 | 2026-11-20 | Audience: Edoardo first, others later. Nothing may block a public release, but first run and other setups aren't designed for yet. Accessibility bar: WCAG AA contrast in light and dark, plus full keyboard use; no VoiceOver work for now. Both are in `docs/PRODUCT.md`. | His answers to `/impeccable init`. | Edoardo |
| 28 | 2026-11-20 | Force Quit asks for a second ⏎: the first turns its row into "Press ⏎ again to force quit <app>", and ⎋, typing or moving the selection puts it back. Quit, a file's Move to Trash and the other actions still run on one ⏎. | Critique finding: Force Quit sits one row under Quit, and a stray ↓ lost unsaved work. A second ⏎ in the row keeps it keyboard-only, with no dialog. | Edoardo |
| 29 | 2026-11-20 | The visual direction is Stage: a tile under the search bar shows what ⏎ will act on (the selected item, the calculator's answer, the clipboard preview) with the keys for ⏎ and ⌘K, over a compact list. Quiet low-opacity fills like Raycast's and no accent-colored selection; color only for meaning (red for Force Quit, orange for a config problem). The selected row ends in ↩, so it doesn't rely on its fill (decision 27). 14 pt rounded corners if step 5 measures them free; otherwise Edoardo decides. The direction contract is in `.impeccable/surfaces/`. | Edoardo picked it from four mockups (Native Tahoe, rofi-dense, Raycast-like, Stage). He turned down the solid blue selection and the impeccable roll's direction (Tokyo rail signage), and asked for an original one. | Edoardo |
| 30 | 2026-11-21 | The app is called Pith: `Pith.app`, bundle ID `dev.edoardo.pith`, config in `~/.config/pith/`, history in `~/Library/Application Support/pith/`, logs under `dev.edoardo.pith`. The Swift modules keep their names (`Launcher`, `LauncherCore`): a launcher is what they are. | Edoardo liked it from Claude's list ("weird, I like it"): the essential part and nothing else. A web search found no Mac app or launcher called Pith; no trademark search yet. | Edoardo |
| 31 | 2026-11-22 | Milestone 3 is the clipboard (`FEATURES.md` §5); the calculator comes after it. Design plan step 7 (polish) comes first, then step 6's brief for the clipboard. The performance pass (milestone 1 step 9, milestone 2 step 8) waits until after milestone 3: ⌘P 23 ms and keystrokes 7–12 ms on screen are decent for now. | Edoardo needs a clipboard manager in his daily use. | Edoardo |
| 32 | 2026-11-22 | An action that fails after the panel has closed posts a macOS notification, as a failed Zip already did: what failed as the title ("Couldn't move notes.md to the Trash"), why as the body, and a click reveals the item. It covers Move to Trash, opening a file, folder or app, Open With… and Open in Terminal. A Move to Trash that fails leaves the item in the history. | Design plan step 7 (harden): failures only went to the log, so a file that silently stayed put looked trashed. Edoardo picked notifications for every action over Trash only, and over reopening the panel, which would pop up over whatever he moved on to. | Edoardo |
| 33 | 2026-11-23 | The clipboard list is newest first whenever the search field is empty. Pinned items are found by typing: pinned matches come first, then the rest newest first. Pins are never dropped by the size or age limits. This replaces "pinned items on top" in `FEATURES.md` §5.3. | The clipboard view has about 5 rows under its preview, and Edoardo mostly reaches for the last few copies; pins on top would push those down. Pins are things you reuse and know, so a few letters find them. | Edoardo |
| 34 | 2026-11-23 | The clipboard opens with ⌘⇧V by default (`[hotkeys] clipboard`, configurable). | The usual hotkey for clipboard managers. It takes Paste and Match Style from every app, and ⌘K → Paste as Plain Text replaces it. | Edoardo |
| 35 | 2026-11-23 | The clipboard history skips copies marked concealed (`org.nspasteboard.ConcealedType`), which password managers such as 1Password, Bitwarden and Apple Passwords set. Everything else is still recorded. | Otherwise passwords sit in plain text in the rows, the preview and the database on disk, and show while sharing the screen. An ignore-app list and a pause hotkey stay open. | Edoardo |
| 36 | 2026-11-23 | The clipboard's in-panel text editor (⌘K → Edit Text) comes after milestone 3, with its own brief once Edoardo has used the clipboard. | Milestone 3 ships recording, browsing, search, paste and the other ⌘K actions sooner. | Edoardo |
| 37 | 2026-11-23 | The clipboard keeps 2 GB and 30 days by default (`[clipboard] max_size_gb`, `max_age_days`). Whichever limit is hit first drops the oldest unpinned items; pins are never dropped. | The spec's example: a month covers "I copied it last week", and 2 GB holds thousands of screenshots. | Edoardo |
| 38 | 2026-11-23 | The clipboard history also skips copies marked transient or auto-generated (`org.nspasteboard.TransientType`, `AutoGeneratedType`). | What nspasteboard.org asks of clipboard managers: text expanders and similar tools use the clipboard briefly, and their copies would fill the history. | Edoardo |
| 39 | 2026-11-23 | ⌘K → Save as File saves at once to `~/Downloads` with a dated name ("Clipboard 2026-11-23 at 14.05.png"), then posts a notification that reveals it on click. | As Zip does: no dialog, keyboard only. | Edoardo |
| 40 | 2026-11-23 | ⌘K → Edit Image comes after milestone 3, with the text editor (decision 36). | Watching Preview for the save is its own piece of work; milestone 3 ships sooner without it. | Edoardo |
| 41 | 2026-11-23 | Builds are signed with a self-signed "Pith Local Signing" certificate in the login keychain, created once with `make certificate`; `make app` falls back to ad hoc without it. | macOS ties Accessibility access (which paste needs) to the app's signature, and an ad hoc one changes with every `make install`. The certificate is tied to no Apple account, unlike Edoardo's existing identities, so no team ID goes into the build. | Edoardo |
| 42 | 2026-11-23 | The launcher has a Clipboard History command, as Raycast does. "c" is its alias: typed alone, it puts the command first, above any app or habit; "clipboard" finds it by name. ⏎ (or a double-click) opens the clipboard in place. ⌘⇧V and the `c ` prefix still open it too. | Edoardo opens the clipboard from the launcher by habit, as in Raycast. An alias rather than a boost keeps "ca" for Calendar, and longer prefixes rank as usual. | Edoardo |
| 43 | 2026-11-23 | In a ⌘K actions list, ⌘Q, ⌘W, ⌘E, ⌘R, ⌘T, ⌘Y and ⌘U run the 1st to 7th action, as ⏎ would on its row; each row shows its letter at its end. The letter is fixed per action (its place in the full list), so a filter doesn't change it. Force Quit and a pinned clip's Delete still take a second press. The letters work only inside ⌘K. A single click still only selects. | Edoardo wants the actions one chord away, under the left hand. In the results list ⌘Q and ⌘W are reflexes (quit, close) and would fire by accident; inside ⌘K they're deliberate. | Edoardo |
| 44 | 2026-11-23 | Pausing clipboard recording lasts through a relaunch: it stays paused until Resume Clipboard Recording, or ⏎ on the clipboard's "Recording is paused" row. Nothing is read while paused, and resuming starts from the clipboard as it is then, so what was copied meanwhile is never recorded. | Pausing is for copying something private, and a restart (login, an update) that silently resumed would record it. The paused row at the top of the clipboard keeps it from being forgotten. | Edoardo |
| 45 | 2026-11-23 | The launcher lists only the recording command that applies: Pause Clipboard Recording while recording, Resume Clipboard Recording while paused. | Nothing in the list does nothing. | Edoardo |
| 46 | 2026-11-23 | Pith isn't notarized, and there's no paid Apple Developer Program: builds go out as zips signed with the local certificate (`make package`, decision 41). Whoever installs one presses Open Anyway in System Settings, Privacy & Security. | Edoardo doesn't want to pay €99 a year. The local certificate still keeps Accessibility access from one build to the next. | Edoardo |
| 47 | 2026-11-23 | Versions are 0.\<milestone\>.\<patch\>, in `Support/Info.plist`; the build number is when it was built. `make package` tags the commit `v<version>`, and refuses uncommitted changes or a version already tagged on another commit. The Quit Pith tile shows "Pith 0.3.0". | A report from someone trying a build points to the exact code. | Edoardo |
| 48 | 2026-11-23 | Pith updates itself with Sparkle, from `pith.edoardobertoli.xyz`: an update feed and the builds as static files on Cloudflare, put there by `make publish`. Sparkle's schedule is off; Pith checks after the panel closes, at most once a day. A found update downloads in the background, then the launcher lists Update Pith, whose ⏎ restarts into it; otherwise it installs when Pith quits. Only a copy in an Applications folder updates. The update check is the second network access, after currency rates, and sends nothing about the Mac. | Patches reach whoever tries Pith without a zip by hand and Open Anyway each time. Hotari already runs the same setup (not notarized, Edoardo's domain). Sparkle is the standard, and the code that decides whether a download is really ours is where a mature library beats our own. | Edoardo |
| 49 | 2026-11-23 | An update says how it went, as a notification: "Pith updated to 0.3.1" once Pith runs the new build, and "Couldn't update Pith to 0.3.1" with the reason when a found update fails to download, pass its signature check or install. A check that can't reach the site (offline, DNS) stays quiet and is tried again an hour later. No progress bar. | The download is done before Update Pith is listed, and ⏎ to the new build running took under a second (0.3.0 → 0.3.1), so a bar would only flash; what was missing was knowing it worked. A failed check needs nothing from you, and offline it would fire every hour. | Edoardo |
| 50 | 2026-11-23 | The launcher has a Check for Updates command. It checks right away, whatever the schedule, and a notification says what it found: "Pith 0.3.3 is ready" (Update Pith then restarts into it), "Pith is up to date", or "Couldn't check for updates" with the reason. The next scheduled check is a day after it. It's listed only in a copy that updates itself, and not while an update is ready. | After `make publish`, Edoardo's own copy would otherwise wait up to a day. Most Mac apps have it, and the result has to be said because the panel has closed. Nothing in the list does nothing (decision 45). | Edoardo |
| 51 | 2026-11-23 | `pith.edoardobertoli.xyz` has a landing page, `site/index.html`, to send to friends or post. It follows the structure of Raycast's landing page (a short claim with Download, a keyboard of key caps with four reasons, alternating feature rows, a personal note, a closing call to action) with Pith's own words, its monochrome Stage look and the real panel snapshots, light and dark. It shows what ships, with the calculator as "coming next", and Edoardo's first-person "why" names Raycast once. The same Worker serves it with the update feed: `make publish` deploys it too, and `make site` deploys only the page. | One link that explains Pith and downloads it, instead of a zip and instructions in a chat. Raycast's page is the structure Edoardo knows; its look and words stay Raycast's. | Edoardo |
| 52 | 2026-11-23 | Pith is free: no price, no paid tier, no account. The landing page says so under Download. | It's a launcher for people who need a launcher (README); nothing in it is held back for a paid tier. | Edoardo |
| 53 | 2026-11-23 | The landing page has motion, in its keys only: they press and ease up, the hero plays a tour of ⌘P, "te", ⌘K and ⌘⇧V once (pausable, pausing off screen and on any input), the ⌘K and ⌘⇧V rows press their keys as they arrive, the config block retypes a value, and the drawn keyboard plays chords. The panel snapshots still change in one frame, and Reduce Motion plays nothing by itself. | Edoardo asked for animation. Putting it in the keys shows how Pith is driven, and keeping the panel instant keeps the one-frame promise. | Edoardo |
| 54 | 2026-11-23 | Pith's app icon is a citrus cross-section in its monochrome: a gray peel, the white pith, ten gray segments with white membranes, on a graphite rounded square. Its source is `Support/AppIcon.svg`; `make icon` draws it into `Support/AppIcon.icns` (committed), which `make app` puts in the bundle. The site uses the same SVG as its favicon and beside the wordmark. | The name taken literally: the pith is the white layer that holds the fruit together. Edoardo picked it from four directions (a P key cap, ⌘P, the panel, the pith). A single image, not an Icon Composer file: there's no Xcode project. | Edoardo |
| 55 | 2026-11-23 | Every key in the panel is configurable, in a `[keys]` table: `up`, `down`, `open`, `actions`, `back`, `preview`, `run_actions` (the 1st, 2nd… action in a ⌘K list, in order) and `to_launcher` (from the clipboard), each one key or a list of alternates. `[hotkeys]` keeps the two global ones, and `""` turns one off; `[]` turns a panel key off, except `open` and `back`, which keep at least one. `[launcher] clipboard_alias` ("c") is Clipboard History's alias, and with a space after it the prefix that opens the clipboard. A key that types (no cmd, alt or ctrl: a letter, Space, ⌫) acts only while the field is empty. ⌘X, ⌘C, ⌘V, ⌘A, ⌘Z and ⇧⌘Z stay the field's editing keys. A key given twice stays with the first setting, and the later line is a config problem with the key left out of it; the same goes for a hotkey or an editing key. Inside ⌘K, `run_actions` comes before `preview`, as ⌘Y does today. The panel shows the keys as configured. | Edoardo wants every keybind in config.toml. A separate table keeps the global hotkeys' stricter rules (they need a modifier) apart; lists keep ⌃K and ⌃J beside the arrows; the typing rule is how Space and ⌫ already behave. First wins reads top-down, as the problems do. An empty hotkey gives Paste and Match Style back to apps. | Edoardo |
| 56 | 2026-11-23 | A first install is a disk image, `Pith.dmg`: its window shows Pith, an arrow and Applications, with how to get past the first open (Open Anyway). The update feed keeps its zips, which Sparkle installs. The landing page and the README link the disk image, and `Pith.zip` is no longer published. | Edoardo doesn't want people to download a zip: dragging into Applications from a disk image is how Mac apps install, and it says where Pith goes. Updates never show the archive, and a zip is what Sparkle handles best. | Edoardo |
| 57 | 2026-11-23 | Pith also installs with one line in Terminal, `curl -fsSL https://pith.edoardobertoli.xyz/install.sh \| sh`, shown in the landing page's setup above the installer's steps; Pith.dmg stays the Download button. `site/install.sh` downloads Pith.dmg, mounts it hidden, installs only a Pith signed with Pith's certificate (decision 41), into /Applications (~/Applications if that isn't writable), replacing and quitting a copy already there, and opens it. | A file curl downloads isn't marked as coming from the internet, so macOS never shows "Pith.app Not Opened" and there's no Open Anyway: the one free way around the dialog Edoardo wants gone, with notarization ruled out (decision 46). Homebrew marks what it installs the same way. The installer stays for whoever won't paste a command. | Edoardo |
| 58 | 2026-11-23 | The Terminal line (decision 57) sits in the hero, under Download for Mac: "or paste this in Terminal, with no Open Anyway" over the command and its Copy. The setup section points to it and keeps the installer's four steps. This replaces decision 57's place for it. | Edoardo asked for it under Download: the first viewport is where people decide how to install. | Edoardo |
| 59 | 2026-11-23 | A mistake in config.toml changes nothing it doesn't have to. A file that isn't valid TOML, is missing or can't be read leaves every setting as it was, and a wrong value leaves its setting as it was; the problem row says so. A setting the file doesn't write has its default. At launch, with no settings yet, a wrong setting gets its default, except a clipboard limit, which then drops nothing until the file sets it right. | A typo used to reset every setting to its default, and the reset `max_age_days` or `max_size_gb` pruned the clipboard at once, for good (step 12's bug check). Keeping what works means Pith can run on a setting the file no longer says until it's fixed; the problem row is there for that. | Edoardo |
| 60 | 2026-11-23 | The folders macOS asks about before an app reads them (Desktop, Documents, Downloads, iCloud Drive) are each read once on a worker of their own, which shows the prompt, and the file index leaves each out until it's allowed: the rest of the home folder is searchable at once, and a folder joins as soon as its prompt is answered. A refused folder is read again each time the panel opens (it doesn't ask again) and joins once allowed in System Settings. Each prompt says why, from Info.plist. The prompts stay at first launch. | One unanswered prompt held back every file result, and a folder allowed later was never scanned. Asking at the first search instead would take the focus from the panel and close it while you type. Edoardo prefers config.toml alone to a settings window that would explain the permissions. | Edoardo |
| 61 | 2026-11-23 | A copy with text or files keeps only those: no image, which is only the app's picture of them (a spreadsheet's cell, Finder's icon). A copy with neither is an image, and only one of its formats is read: PNG, else TIFF, JPEG or HEIC. Pasting a text clip back gives its text and formatting, not the app's picture of it. | Reading a type makes the app that copied render it: every cell copied rendered a picture that was stored with the text, memory spiked at each copy, and the 2 GB filled sooner. A screenshot also rendered a TIFF of about 59 MB that was then dropped. | Edoardo |

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
    Item.swift             Item (an app, file, folder or Command) with a stable id; Command (Clipboard History, Pause and
                           Resume Recording, Clear Clipboard History, Update Pith, Check for Updates, Open and Reload
                           Config, Quit) and its aliases
    SearchKey.swift        text → lowercased, diacritic-folded UTF-8 + per-byte bonus + 64-bit byte mask
    KeyStore.swift         many search keys in four flat buffers (for the file index)
    FuzzyMatcher.swift     query × key → score (fzf v2-style dynamic programming)
    QueryTerms.swift       a query split into words, at spaces and `/`, each matched on its own
    SearchIndex.swift      apps and commands + keys + id lookup; scored search with boosts
    FileIndex.swift        files and folders as a tree in flat arrays, O(1) path lookup, parallel top-k search
    FileScanner.swift      fts walk of the configured folders; IgnoreRules; FileRules
    FileSearchEngine.swift owns the FileIndex on a serial queue: rebuilds, FSEvents patches, searches
    History.swift          what was opened and when: recent list, frecency, boosts for apps and files
    Zipper.swift           Finder-style zip with ditto, next to the original, numbered when taken
    Clip.swift             a clipboard clip (kind, when, source, pin, text start), its content and representations
    ClipboardStore.swift   the clipboard history on disk, on its own serial queue: SQLite, image files, retention
    SQLiteDatabase.swift   a thin wrapper over the system SQLite: open, prepare, bind, step, transactions
    ImageThumbnails.swift  a copied image's row and preview thumbnails, decoded by ImageIO at their exact pixel sizes
    ClipReading.swift      a copy's pasteboard items → a clip: the types read, markers skipped, kind, text, PNG
    ClipboardIndex.swift   the clipboard history in memory, newest first: word search, pins first, parallel when long
    AppScanner.swift       walks the app folders (+ Finder) → [Item] with resolved-path ids
    DirectoryWatcher.swift FSEvents → folders or per-file events with flags, with source-level exclusions
    Config.swift           config.toml settings, defaults, problems with line numbers, the commented template
    TOMLReader.swift       a small strict TOML reader (the subset the config needs)
    Shortcut.swift         "cmd+shift+p", "ctrl+k", "up" → key code + modifiers; global or typing; symbols, key caps
    KeyBindings.swift      `[keys]`: each panel key's shortcuts, with first-wins conflicts and their problems
  Launcher/                the AppKit app, main actor by default
    main.swift             NSApplication with the accessory policy
    AppDelegate.swift      wiring: panel, config → hotkey/empty state/login item, commands, index (re)builds; Log
    Background.swift       runInBackground: blocking work on a GCD worker, awaited from the main actor
    ConfigStore.swift      ~/.config/pith/config.toml: create, read and parse on a worker, reload on change, open
    HistoryStore.swift     the History, loaded and saved as JSON on workers
    RunningApps.swift      open apps in MRU order: runningApplications re-read on launch/quit and on show
    LoginItem.swift        SMAppService registration, for a copy in an Applications folder only
    HotKeyCenter.swift     global hotkeys via Carbon RegisterEventHotKey; GlobalHotkeys, the configured ones by name
    KeyLayout.swift        the key that types a letter in the keyboard layout in use, for the hotkeys and the paste's ⌘V
    LauncherPanel.swift    the NSPanel: show/hide, collapse/expand, key events to the panel's keys, the search field's editor
    LauncherViewController.swift  rows, merged app + file search, empty state, ⌘K sublists, the keys' lookup, opening
    Actions.swift          ⌘K actions per kind, the SF Symbols rows use, AppResolver (config app names, Open With…)
    IconStore.swift        app, symbol and file-type icons as exact-size bitmaps rendered off the main thread; apps
                           by bundle id (a clip's source), looked up on a worker
    ResultViews.swift      one-line cell (name, folder, "running", ↩), the tile (StageView) and its keys, bitmap IconView,
                           row view (the quiet selection)
    Palette.swift          the few colors the system doesn't have: quiet gray, fills, edge, red and orange
    Notifier.swift         notifications for a finished Zip and failed actions, reveal on click
    ClipboardRecorder.swift  the pasteboard's change count on a timer (off while paused); each new copy read,
                           classified and stored
    ClipboardHistory.swift the ClipboardIndex, loaded at launch and updated by each recorded copy; prunes to
                           `[clipboard]`'s limits
    ClipboardPresentation.swift  a clip's words in its row and on the tile: titles, ages, sizes, notices
    ClipImages.swift       copied images' thumbnails as bitmaps, read on a worker, the newest ready ahead of time
    Paste.swift            a clip back on the pasteboard, ⌘V posted, Accessibility, the clip's ⌘K actions, save names
    Updater.swift          Sparkle, checked after the panel closes at most once a day; a ready update's install,
                           and how it went
Support/Info.plist         bundle metadata (bundle ID, LSUIElement, Sparkle's feed and key), copied in by `make app`
Support/AppIcon.svg        the app icon's source (decision 54); `make icon` redraws AppIcon.icns and Assets.car from it
Support/Assets.car         the same icon as an asset catalog (`CFBundleIconName`), as macOS 26 apps carry it
Support/DMGBackground.svg  the installer window's background (decision 56); `make icon` redraws its PNGs at 1x and 2x
Support/dmg-settings.py    the installer's layout for dmgbuild: Pith and Applications side by side
Support/dmgbuild-requirements.txt  dmgbuild and its two libraries, pinned by hash
Support/wrangler.toml      pith.edoardobertoli.xyz on Cloudflare, where `make publish` puts the feed and the builds
site/index.html            the landing page (decision 51): one file, served with snapshots from docs/snapshots/
```

Files the app keeps:

| File | What | Written |
|---|---|---|
| `~/.config/pith/config.toml` | Settings (FEATURES §8) | Created with commented defaults on first launch; then only by you |
| `~/Library/Application Support/pith/history.json` | What you opened and when (≤ 200 items × 10 times); deleted files are dropped | After every open or deletion, on a serial worker, atomically |
| `~/Library/Application Support/pith/clipboard/` | The clipboard history: `history.sqlite` (clips, their text and what a paste puts back) and `images/` (each image and its two thumbnails), and `paused` while recording is paused (decision 44). `[clipboard]`'s limits, 2 GB and 30 days by default, pins kept | After each copy, on the store's serial queue |
| `~/Library/Preferences/dev.edoardo.pith.plist`, `~/Library/Caches/dev.edoardo.pith/` | Sparkle's state (its last check) and a downloaded update until it's installed; the update that's ready (`PendingUpdate`), for the next launch to report | By Sparkle, after a check (decision 48); by Pith when an update is ready or Update Pith is chosen, and read once at the next launch (decision 49) |

**Startup.** `AppDelegate` builds and draws the panel, loads the history, then the config, and registers the
configured hotkey. The clipboard history is loaded (its index built on a worker) and pruned to `[clipboard]`'s
limits once the config is read, so nothing is dropped by limits it doesn't set. A pause saved before the relaunch is
applied, and only then does the recorder start watching, from what's on the clipboard now. Sparkle isn't started at
launch: the first time the panel closes, it starts and checks for an update. If an update was ready before this launch,
it's read on a worker and a notification says how it went. The app folders and Finder are scanned on a worker, and the launcher's commands are added, minus
the launcher itself. The new `SearchIndex` goes to the view controller, which has `IconStore` render the icons it
doesn't have yet. FSEvents streams trigger a rescan when the app folders change (unless the change is inside a bundle)
and a reload when the config's folder changes. The newest rescan or reload always wins. The file index's first scan
leaves out the folders whose privacy prompt isn't answered yet, each read on a worker of its own, and is rebuilt as
each is allowed (decision 60).

**Config.** A bad setting stays as it was and becomes a problem with its line number; a file that isn't valid TOML, or can't be read, changes nothing (decision 59). At launch a bad setting has its default, except a clipboard limit, which drops nothing until it's set right. Problems are listed first in
the empty state, and ⏎ on one opens the file. A changed hotkey is registered before the old one is let go, so if the
new one is taken, the old one keeps working. Launch at login registers or unregisters only when the setting changes,
and only for a copy in an Applications folder.

**⌘P.** The Carbon handler runs on the main thread with the key press's timestamp. The view controller fills in the
empty state first, so the panel appears at its final size. The panel is then moved to the screen under the mouse
pointer and made key without activating the app. The time from the key press to the panel being drawn goes to the
`perf` log. ⌘⇧V does the same in clipboard mode: its rows come from the in-memory `ClipboardIndex`, and the newest
images' thumbnails are already decoded. Either hotkey closes the panel in its own mode and switches the other.

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

**Keys.** Every key press reaches the panel's `sendEvent` (or `performKeyEquivalent`, for chords) before the field
editor, and one lookup turns it into what `[keys]` says it does (decision 55): `back` and `open` first, then `up`,
`down`, `actions`, `preview` and `to_launcher`, with `run_actions` ahead of them all in a ⌘K list. Letters and
punctuation match by the character they type in the current layout (with ⌘ alone applied, as menus do), other keys by
position. A key that types acts only on an empty field and otherwise goes on to it; an input method that is composing
text keeps every key. A ⏎ or ⎋ that isn't a panel key does nothing rather than end the field's editing. ⌘X/C/V/A/Z
and ⇧⌘Z are routed by hand after the lookup, because an agent app has no main menu to do it. The tile's keys, the
action rows' shortcuts and the selected row's ↩ show the first key of each setting.

**⌘K.** On an app row, ⌘K replaces the list with its actions: Open and Reveal in Finder, plus Quit and Force Quit if
it's running. The search field filters them, ⏎ runs one, and ⎋ or ⌘K goes back to the search and selection you had.
Force Quit waits for a second ⏎ (decision 28); ⎋, typing or moving the selection cancels it. Quitting goes through
`quitApp`, which tests swap out so they never quit a real app.

**Opening.** ⏎ or a double click records the item in the history, hides the panel, then launches the app (or brings
it to the front) or runs the command. Losing focus also hides the panel. Every hide empties the field.

### Threads

| Thread | Runs | Never |
|---|---|---|
| Main | Events, the hotkey handler, NSWorkspace callbacks, the app search, merging results, table updates, applying results | File I/O, icon rendering, IPC, waiting on anything (the one exception: resolving a newly launched app's bundle path, once per process) |
| Serial GCD queue `launcher.files` (`.userInitiated`) | Owns the file index: searches (spread over the cores with `concurrentPerform`), FSEvents patches (one `lstat` each), subtree rescans | Touching UI |
| GCD worker (`runInBackground` or `global`) | Full file scans (`.utility`); reading a protected folder once, which waits on its privacy prompt (decision 60); the app scan and index build; config reading, parsing and app resolution; loading the history; opening files; Reveal, Copy, Trash, Zip (`ditto`, `.utility`); Open With… choices; login item registration; writing a clip to the pasteboard and posting ⌘V; Save as File; the Accessibility check; a source or link app's lookup | Touching UI or shared state |
| GCD workers (`concurrentPerform`, one per core, `.userInitiated`) | Rendering missing icons in parallel, each into its own slot; scanning the older half of a long clipboard history when the newest clips don't fill the list | Touching UI or shared state |
| Serial GCD queue `launcher.history` (`.utility`) | Saving the history, in order; quitting waits for it | Touching UI or shared state |
| Serial GCD queue `launcher.clipboard.watch` (`.utility`) | The clipboard timer: reads the change count, and on a change the copy's types and data | Touching UI |
| Serial GCD queue `launcher.clipboard` (`.userInitiated`) | Owns the clipboard database and image files: stores, prunes, loads, reads for a paste | Touching UI |
| Swift cooperative pool | Only awaiting; nothing blocks on it | Blocking calls |

At idle, one thing is scheduled: the clipboard's change-count check every 0.5 s, with 0.25 s of leeway, stopped while the screens sleep. macOS has no notification for a new copy. Nothing else polls, and workers exist only while there is work.

### Matching and ranking

- Text is folded once: diacritics removed (`Café` → `cafe`), lowercased, kept as UTF-8. ASCII names take a fast path
  that never creates a `String`.
- A 64-bit mask of the bytes present rejects most non-matches with one AND. A forward scan then checks that the query
  is a subsequence and narrows the columns the dynamic programming has to cover.
- Scores follow fzf: a match is worth 16, a gap costs 3 plus 1 per extra character. Bonuses go to word starts (10
  after whitespace, 9 after `/,:;|`, 8 after other punctuation), camelCase humps and digits (7), and runs of
  consecutive matches. The first query character's bonus counts double. Leading and trailing text is free.
- Apps match on their localized name and, when it differs, on their file name, so "calcu" finds Calcolatrice.
- Words (decision 23): the query splits at spaces and `/`, and every word must match. The scores add up, so more
  words in the name rank higher. For files, the last word must match the name, and each earlier word must match the
  name or a folder above it, at half weight. Folder scores are computed once per search, in one pass down the tree
  (parents always come before children), so a path word costs one score per folder rather than per file. `~` and `.`
  are skipped, so `~/Projects/acme/deploy` works.
- Ranking: match score plus the history boost, then shorter name, then alphabetical. The boost is
  `min(48, 12 · log2(1 + frecency / 100))`: one open today is worth +12, a daily habit tops out at +48 (about three
  well-placed characters), so habits reorder close matches without burying a clearly better one.
- A command's alias (decision 42: "c" for Clipboard History) puts it first when the query is exactly the alias,
  above any score or habit; any other query ranks it as usual.
- The clipboard doesn't match fuzzily: each query word must appear in the clip as written, ignoring case and
  accents, and results stay newest first, with pins first when typing (decision 33). Long texts would let a fuzzy
  query match almost anything. `docs/MILESTONE-3.md` step 3 has the numbers.

### Icons

The first draw of an app icon costs ~5 ms on average and ~38 ms at worst (measured over 108 apps), because IconServices
renders the layered icon on demand. Drawing it on the main thread while typing is what made the first build stutter.
Now `IconStore` renders every app's icon once, right after indexing. It works on all cores, into BGRA bitmaps at the two
sizes the panel shows: 40×40 px for the rows and 96×96 px for the tile (20 pt and 48 pt at the screen's scale). A row or
the tile only sets the bitmap as its layer's contents. 111 apps take ~4.8 MB in all: 0.7 MB for the rows and 4.1 MB for
the tile (the single 28 pt size before Stage took ~1.4 MB). A row whose icon isn't ready yet shows none until the batch
lands. File icons are rendered by type on first request, with the type's name ("PDF document") for the tile.
Commands, actions and problems use SF Symbols, rendered the same way: in the quiet gray, a problem's in orange and
Force Quit's in red too, and at tile size for the commands and problems.

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
| File search | 0.1–0.3 ms for one word, 0.2–0.4 ms for two or three (35k entries); up to 0.7 ms at 100k; round trip from the main thread 0.1–0.2 ms | `make bench` |
| Keystroke work in-process (apps + 35.6k files, merge, update the rows and the tile, render; offscreen) | ~2.0 ms (1.9 ms before Stage, same session) | `make bench` (UIBenchmark) |
| ⌘P work in-process (sync running apps, fill the empty state, lay out, draw; offscreen) | 0.4–0.5 ms recent (8 rows), 0.45 ms running (111 rows), 0.2 ms none | `make bench` (UIBenchmark) |
| FSEvents → file searchable | about 0.5–1 s (0.5 s coalescing) | tests |
| ⌘P → panel drawn, on screen | Stage build, clear window with round corners: 23 ms, almost all "update" (one sample); milestone 2 build: ~27 ms | `make logs` |
| Keystroke → results drawn, on screen (apps + 35.6k files) | Stage build: typically 7–12 ms: delivery 2–3, update 4.7–6, draw 0–2; a few at 19–22 ms with 8–13 ms of delivery. Milestone 2 build: 7–10 ms | `make logs` |
| Footprint 25 s after launch, untouched | Stage build 39 MB, the milestone 2 build 30 MB, measured the same way. 5.9 MB of the Stage build is the tile's 96 px icons: 123 bitmaps of 36 KB, each in its own 48 KB block | `make stats`, `footprint` |
| Idle (milestone 2 build) | 24 MB footprint, 0% CPU, 6 threads | `make stats` |

## Visual decisions

Stage, the direction Edoardo picked (decision 29); the values are Claude's (decision 25). Every state, light and dark,
is in `docs/snapshots/` (`make snapshots`).

| Element | Choice | By |
|---|---|---|
| Panel | 680 pt wide. Only the 52 pt search bar when there are no results (FEATURES §4); 423 pt when there are: the bar, the tile with an 8 pt margin around it, 8 rows of 32 pt and 6 pt under them. The top edge stays fixed. It keeps that height with fewer rows (FEATURES §2: a fixed size), so the panel doesn't jump while you type and the tile, keys and rows never move. | Claude |
| Surface | The window background color in a rectangle with 14 pt continuous corners and a 1 pt edge (black 12 % light, white 14 % dark), with the system shadow. The window itself is clear so the corners can be round; the fill, corners and edge are layer properties, so the compositor draws them and growing or shrinking repaints nothing. No glass or blur. | Claude |
| Position | On the screen under the mouse pointer, which is how "the active screen" is defined. The expanded panel would be centered, and the search bar is its top edge. | Claude |
| Grid | The bar and the rows share one: icons start 18 pt from the panel's side (10 pt inside the selection), and the magnifying glass is centered on their column. Names and the query start at 48 pt. | Claude |
| Type | Search field 20 pt with a "Search" placeholder ("Filter actions", "Filter apps" in ⌘K). Rows 14 pt with 20 pt icons, the folder after the name at 12 pt. The tile: name 19 pt semibold, folder and kind 12 pt. Names and folders cut in the middle. | Claude |
| Tile | Under the bar, 92 pt, 10 pt corners, a faint fill (black 3.5 % light, white 4.5 % dark). It shows what ⏎ acts on: a 48 pt icon, the name, the folder, and the kind with when it was last opened ("PDF document · opened today at 14:05") or "running". In ⌘K and Open With… the item stays on it. On the right, two keys as words with key caps: what ⏎ does in bold (Open, the selected action, Open in Preview, Open Config, Run), then "Actions ⌘K", or "Back esc" one level down. Key caps are the selection's fill with their glyph in the Key color, the same as the row's ↩ (8.8:1 light, 7.4:1 dark on the cap). | Claude |
| Selection | A quiet rounded rectangle (7 pt corners, black 7 % light, white 10 % dark), inset 8 pt from the panel's sides, drawn by our row view on a plain table. The fill alone is 1.2:1 and 1.4:1, so the selected row also ends in ↩ in the Key color (#3C3C3C light, #D6D6D6 dark: 9.4:1 and 8.4:1) and the tile names the item (decision 27). Scrollers are always overlay. | Claude |
| Quiet gray | Folders, kinds, "running", the second key's words and symbols: #666666 light, #A1A1A1 dark, opaque. 4.9:1 and 4.75:1 on the selection, its darkest background. | Claude |
| Color for meaning | Force Quit waiting for its second ⏎: red text and symbol (#D70015 light, #FF6961 dark) on a faint red row, and the tile's key in red. A config problem: its symbol in orange (#C93400 light, #FF9F0A dark; the system orange is 2.2:1 on white). No accent color anywhere. | Claude |
| Running indicator | "running" after the name, in the quiet gray; on the tile, "Application · running". | Claude |
| Commands, actions, problems | SF Symbols in the quiet gray in place of an icon: gearshape, arrow.clockwise, power for commands; arrow.up.forward.app, folder, link, square.grid.2x2, terminal, doc.on.doc, doc.zipper, trash, xmark.circle, xmark.octagon for actions; exclamationmark.triangle for problems. A problem row reads "Config problem, line N: …"; on the tile, "Config problem, line N" over the problem, capitalized unless it starts with a setting's name. A file that isn't valid TOML adds "so the settings stay as they were", or at launch "so every setting is at its default and no clipboard history is dropped". Commands say "Pith command" on the tile. | Claude |
| ⌘K | Sublists replace the list in place; the item stays on the tile. ⎋ steps back one level as it was; ⌘K goes back to the search. Each action row ends in its shortcut ("⌘Q"…"⌘U", decision 43) in the quiet gray, as menus show theirs, before the ↩ on the selected row. | Claude |
| Motion | None: the panel appears and disappears without animation. | Claude |
| Clipboard mode | The same panel and height (docs/BRIEF-CLIPBOARD.md). The bar shows `doc.on.clipboard` and "Search clipboard". The tile grows to 188 pt (92 + 3 rows), so five whole rows fit under it. Everything in the tall tile hangs from the top, keys included, so nothing moves from one kind to the next. | Claude |
| Clipboard preview | A text: its first 8 lines in SF Mono 12 pt, label color, wrapped, the 8th ending in "…" when there's more; under it, at the bottom, "Text · 10 lines · copied today at 14:28 from Terminal". An image: fitted into a box up to 320 × 156 pt, never past its own pixels, 6 pt corners, on a checkerboard of 6 pt squares (selection fill) for transparency, with "Image", its size and when it was copied beside it. A link or files: the launcher's tile, the URL wrapped over up to 3 lines and cut in the middle past them. | Claude |
| Clipboard rows | The source app's icon for texts and links (the kind's symbol when the app isn't installed), a 20 pt thumbnail with 4 pt corners for images, the file's icon for files. Text titles are the first line, cut at the end; links and files are cut in the middle. At the end, the age in the quiet gray ("now", "5 min", "14:05", "yesterday", "Tue", "Oct 31"), after `pin.fill` at 10 pt for a pinned clip. | Claude |

## Libraries

One third-party dependency: Sparkle, for updates.

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
| History storage | JSON via `Codable` (system) | ≤ 200 small entries, so SQLite would be overkill. |
| Launch at login | `SMAppService.mainApp` (ServiceManagement, system) | The current API; no helper app needed. |
| Running apps | `NSWorkspace` notifications (system) | Launch, activation and quit events, so no polling. |
| File walk | `fts` (libc) with `FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV | FTS_NOSTAT` | As fast as `find`; no stat per file, no symlink following, no crossing into mounts. `FileManager`'s enumerator is slower and allocates a URL per entry. |
| File types | UniformTypeIdentifiers (system) | Package detection, file-type icons, `[open_with]` type matching. |
| Shared state for stale searches | `Atomic` (Synchronization, toolchain) | One relaxed integer, so no lock. |
| Zip | `/usr/bin/ditto` via `Process` (system) | What Finder's Compress uses (FEATURES §4.4): same format, resource forks kept. |
| Quick Look | `QLPreviewPanel` (Quartz, system) | The system preview; the launcher acts as its controller. |
| Notifications | UserNotifications (system) | For a finished Zip and failed actions (decisions 21, 32). |
| Clipboard storage | SQLite through the system `SQLite3` module, behind a small wrapper (`SQLiteDatabase`) | Thousands of entries written one at a time, each copy an atomic insert. The history lives in memory for search, so the database only loads and saves. GRDB, the `FEATURES.md` candidate, is excellent but would be the first third-party dependency for a handful of queries. |
| Clipboard thumbnails | ImageIO `CGImageSourceCreateThumbnailAtIndex` (system) | Decodes straight to the exact pixel size without loading the full image. |
| Clipboard duplicates | SHA-256 from CryptoKit (system) | A copy of content already in the history must find it, and a collision would move the wrong clip, so a 64-bit hash isn't enough. |
| Watching the clipboard | `NSPasteboard.changeCount` on a GCD timer with leeway | macOS has no notification for a new copy, so this is the only way; leeway lets the system coalesce the wakeups. |
| Paste | `CGEvent` ⌘V posted to the annotated session tap (CoreGraphics, system), after the pasteboard is written, on a worker, on the key that types V in the layout in use | How every clipboard manager pastes; it needs Accessibility access (`AXIsProcessTrusted`, checked on a worker at launch and each time the clipboard opens). |
| Keyboard layout | Text Input Sources and `UCKeyTranslate` (Carbon, system), on the main thread: the key that types a letter with ⌘ held, in the layout in use or the last one with letters | A hotkey or ⌘V named by its letter lands where the layout puts it (Dvorak, Colemak), as menus do; hotkeys are registered again when the layout changes. |
| Updates | [Sparkle](https://sparkle-project.org) 2.10.1, pinned, from its Swift package; `make app` embeds its framework and signs it with the app (decision 48) | The standard updater for Mac apps outside the App Store, since 2006: EdDSA-signed feeds, a check that the update is signed like the app, install and relaunch. Hotari uses the same version. An updater of our own would mean owning the code that decides whether a download is ours. Its schedule is off, so it adds no timer; it starts on the first check, after the panel closes. |
| The icon as an asset catalog | `actool` (Xcode), run by `make icon` on the icon's sizes, no Xcode project; the compiled `Assets.car` is committed | A macOS 26 app names its icon in an asset catalog (`CFBundleIconName`) besides the `.icns`, as Hotari does. Added while chasing the blank notification icon on Edoardo's Mac, which is still open (`docs/MILESTONE-3.md` step 11). The catalog holds the same single image as the `.icns` (decision 54), not an Icon Composer file. |
| Installer disk image | [dmgbuild](https://github.com/dmgbuild/dmgbuild) 1.6.5 with ds_store 1.3.1 and mac_alias 2.2.2, pinned by hash in `Support/dmgbuild-requirements.txt`, in a venv under `.build` (decision 56) | Writes the window's layout (icon places, background, hidden bars) straight into the image's `.DS_Store` with the image mounted hidden, so no Finder window opens on the Mac building it. create-dmg lays the window out by scripting Finder, which puts windows on screen; `hdiutil` alone makes an image with no layout. A build tool, not shipped in the app. |
| Hosting the updates and the landing page | Cloudflare static assets on `pith.edoardobertoli.xyz`, deployed with wrangler 4.166.0, pinned, its telemetry off (`npx`, `Support/wrangler.toml`) | The domain is already on Cloudflare; static files need no server, and the zips stay out of git. One deploy carries the page, its snapshots, the feed and the builds (decision 51). |
| Tests | Swift Testing (toolchain) | The current standard over XCTest. |
| Panel snapshots | `NSView.cacheDisplay(in:to:)` into a 2× bitmap, written as PNG (AppKit, system) | Draws real panels that are never on screen, so it runs anytime. swift-snapshot-testing would add a dependency for image comparisons we don't do. |
| Formatting | swift-format (toolchain), configured in `.swift-format` | Ships with Swift, so nothing to install. |

