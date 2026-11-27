# Milestone 3: the clipboard

Goal: Pith keeps a history of what you copy and pastes any of it back from the keyboard: ⌘⇧V, a glance, ⏎ (decision
31). It records text, links, images and files, opens in one frame, searches in under 5 ms per keystroke, and stays
under 50 MB idle. The design is `docs/BRIEF-CLIPBOARD.md`. Two pieces of `FEATURES.md` §5 come later: the in-panel
text editor and Edit Image (decisions 36, 40).

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Storage and retention

Status: **done**.
- `ClipboardStore` keeps the history in `~/Library/Application Support/pith/clipboard/`: a SQLite database (the system
  library) for the clips, their text and the pasteboard types they came with, and an `images` folder with each image
  and its two thumbnails, rendered once with ImageIO at their exact pixel sizes (40 px for rows, the preview box at 2x).
- Each clip records its kind (text, rich text, link, image, files), source app, time, pin and size.
- Retention: 2 GB and 30 days by default (decision 37), oldest unpinned first; pins are never dropped and don't count
  toward the size (decision 62). Applied at launch, after each copy and when the config changes the limits: no timer.
  A limit that would drop clips applies only once it has stayed set for a minute (decision 76).
- Every call runs on the store's serial queue, `launcher.clipboard`, off the main thread and Swift's cooperative pool.
- In memory, a clip keeps only the first 4,096 characters of its text (files: about 2,500 paths); the rest stays on
  disk for the paste. Duplicates are matched by a SHA-256 of the kind, every representation and the image.
- Deleting gives the space back (incremental vacuum, image files removed); files a crash left without their clip are
  removed at load.
- Tested on temporary folders, never the real `~/Library/Application Support/pith/`.

## 2. Recording

Status: **done**. Built and tested on a private pasteboard.
- `ClipboardRecorder` reads the pasteboard's change count every 0.5 s on its own queue, `launcher.clipboard.watch`,
  with 0.25 s of leeway so the system can coalesce wakeups: macOS has no notification for a new copy. It stops while
  the screens sleep, another user's session is in front, or recording is paused. What's on the clipboard at launch
  isn't recorded.
- macOS can deny an app the clipboard (`accessBehavior`): then nothing is read, and the clipboard says so.
- Skipped: copies marked concealed, transient or auto-generated (decisions 35, 38), checked on the types alone, so a
  password's data is never fetched.
- Read: only the standard types apps paste with (plain and rich text, links, file URLs), and an image (PNG, TIFF, JPEG,
  HEIC, the first an item has) only when there's no text and no file (decision 61). Reading a type makes the app that
  copied render it, so nothing else is read.
- Classified by `ClipReading`: files first; an image only without text (converted to PNG unless it is one, and taken
  out of rich text when it comes only there); text that is one URL is a link; text with RTF or HTML is rich text.
- Source: the copy's `org.nspasteboard.source` marker, otherwise the app in front when it was copied: another app
  coming to the front reads a pending copy first. What Pith puts back carries a marker of its own, so its source is
  never the app it's pasted into. A copy already in the history moves that clip to the top with its pin, and an unknown
  source doesn't overwrite a known one.

## 3. History in memory and search

Status: **done**.
- `ClipboardIndex` holds the clips newest first, each with a search key prepared when it arrives: text and links by
  their text, files by their names, images not at all.
- Every word of the query must appear in the clip as written, in any order, ignoring case and accents: in a
  4,096-character text the letters of almost any short query appear in order, so fuzzy matching doesn't fit. A 64-bit
  mask rejects most clips at once; `memmem` checks the rest.
- Newest first; when typing, pinned matches first (decision 33). The newest clips are scanned first, and the rest is
  split over the cores when they don't fill the list.
- `ClipboardHistory` loads the history at launch, builds the index on a worker, and only then starts the recorder.
  It loads it again as the clipboard opens if another program changed the database (decision 73); a clip the store no
  longer has leaves the list when it's used.
- Speed (`make bench`, 5,000 clips): a query as you type it 0.01–0.04 ms; a word that matches nothing 1.1–1.5 ms; at
  worst, with every clip at the 4,096-character cap, 2.4 ms. The index builds in 27 ms (186 ms at the cap).

## 4. Clipboard mode in the panel

Status: **done**. Built from the brief (§3, §5, §7); the `clipboard-*` snapshots show every kind and state, light
and dark, with AA contrast.
- `LauncherViewController.Mode`: the same panel, opened in clipboard mode by ⌘⇧V (`[hotkeys] clipboard`, decision 34),
  `c ` as the whole query, or Clipboard History (decision 42); ⌫ on the empty field goes back. Each hotkey closes the
  panel in its own mode and switches it from the other.
- The bar shows the clipboard symbol and "Search clipboard"; the tile is 188 pt and is the preview (`TileView.Preview`):
  a text in SF Mono, an image in its box on a checkerboard, a link or files as items, a long URL over three lines.
- Rows per kind with ages and pins: `ClipText` gives the words, `ClipImages` the thumbnails, decoded on a worker, the
  12 newest clips' ready ahead of time, so ⌘⇧V draws without touching the disk. `IconStore` finds a source app by
  bundle id on a worker; a row shows the kind's symbol only once the app is known to be missing.
- A copied file's existence and size are read on a worker (`FileFacts`).
- States: the empty history (the tile alone), "Pith can't read the clipboard" (⏎ opens Privacy & Security), "Recording
  is paused" (step 6). Quick Look (⌘Y, Space) previews an image or the first file.
- Departures from the brief: dates read "Oct 31", as the launcher's do; sizes follow the Mac's region format.

## 5. Paste and the ⌘K actions

Status: **done**. Tested with delivery swapped out, so tests never type into your apps or touch the clipboard; paste
itself is one of the checks on the installed build before each release (`docs/RELEASING.md`).
- ⏎ pastes, or without Accessibility access copies, asks for access once per launch, and lists "Paste needs
  Accessibility access" first (⏎ opens the setting). Access is checked on a worker at launch and each time the
  clipboard opens.
- A paste writes everything the clip was copied with, naming its source app, so the recorder moves the clip to the
  top instead of recording it again. Paste as Plain Text writes the text alone, marked transient, and moves the clip
  itself.
- ⌘K: Paste, Copy to Clipboard, Paste as Plain Text, Open in… (`[open_links]`'s app, else the default), Reveal in
  Finder (it says when the files are gone), Save as File (`Clipboard 2026-11-23 at 14.05.txt` in Downloads, decision
  39), Pin, Delete (a second press for a pinned clip, or from its shortcut: decision 74). Pin and Delete keep the panel
  open and the place in the list.
- ⌘Q…⌘U run the 1st to 7th action of any ⌘K list (decision 43). Failures post a notification (decision 32).
- `make certificate` creates the "Pith Local Signing" certificate once (decision 41), so Accessibility access survives
  updates.

## 6. Commands and config

Status: **done**.
- Pause and Resume Clipboard Recording, only the one that applies listed (decision 45). Paused, the recorder's timer
  is off; resuming starts from the clipboard as it is then. The pause is a `paused` file and lasts through a relaunch
  (decision 44); "Recording is paused" comes first in the clipboard, and ⏎ on it resumes.
- Clear Clipboard History asks for a second ⏎ in red; its tile says "Pinned items stay".
- `[clipboard] max_size_gb` (more than 0, at most 1000) and `max_age_days` (1 to 3650), 2 and 30 by default:
  `ClipboardHistory` prunes after the load, after each copy and when the config changes them, never before the config
  is read.
- `[open_links]`: URL scheme → app, resolved like `[open_with]`; `https` covers `http` unless `http` has its own, and
  `"https:"` or `"https://"` mean `https`. A wrong value, or an app that isn't found, is a problem row.

## 7. Updates

Status: **done** (decisions 48–50).
- `Updater` wraps Sparkle 2.10.1. Sparkle's schedule is off: Pith checks after the panel closes, at most once a day
  (an hour after a failed check), and Sparkle starts only then, so nothing runs at launch and there's no timer.
- A found update downloads in the background, is checked against the key in Info.plist and the app's own signature,
  then waits: Update Pith, listed above the recent items, installs and relaunches; otherwise it installs when Pith
  quits. Only a copy in an Applications folder updates.
- Each outcome is a notification (decision 49): the next launch says "Pith updated to 0.3.1" or, if Update Pith was
  chosen and it didn't take, "Couldn't update"; a failed download or install says so at once. A check that can't reach
  the site stays quiet. Check for Updates (decision 50) always reports.
- `make publish` packages and tags the build and deploys the feed, the versioned zip and `Pith.dmg` to
  `pith.edoardobertoli.xyz` (`docs/RELEASING.md`). Sparkle makes the app 4.9 MB.
- Measured on Edoardo's Mac: an update downloads about 11 s after the panel closes, and ⏎ to the new build running
  takes under a second.

## 8. Performance

Status: **done**, with memory after use over the 50 MB target (decision 77). `make bench` on a month of history,
5,000 clips with 312 screenshots: loading it at launch 5.8 ms, ⌘⇧V → drawn 1.4 ms, a keystroke in the clipboard
0.16 ms; a search 0.01–1.6 ms, 2.4 ms at worst; the clips and their keys take 6.9 MB. The launcher's keystroke is
2.3–2.9 ms of work. Memory, by use (step 13): 43 MB at launch, 53 MB after searching, the clipboard and pasting, 63 MB
after a first Quick Look, and up to 90 MB after scrolling a long PDF in it; 0 % CPU and 5 threads idle.

## 9. Design review

Status: **todo**.
- An impeccable critique and polish of clipboard mode against the brief, on the snapshots.
- `docs/DESIGN.md`, through its full text: the 188 pt tile, the SF Mono preview, orange for any setup problem. The
  values go in the Visual decisions table.

## 10. Configurable keys

Status: **done** (decision 55).
- `Shortcut` reads any key (`cmd+k`, `ctrl+j`, `up`, `space`), and knows whether it can be a global hotkey and whether
  it types. `Config` reads `[keys]` (a key or a list each), `[launcher] clipboard_alias`, and `""` for a hotkey.
- A value that isn't a key keeps its setting; a key given twice, a hotkey's key or an editing key (⌘X C V A Z ⇧⌘Z) is
  left out of the later setting; `open` and `back` can't be empty.
- One lookup turns a key press into what it does, before the field editor; a key that types acts only on an empty
  field, and ⌘K lists check `run_actions` first. The tile's keys, the action rows' shortcuts and the selected row's ↩
  show the configured keys.

## 11. First install

Status: **done** (decisions 56–58, 67). 0.3.5 was the first release with the installer and the landing page.
- `make package` also makes `Pith-<version>.dmg` with dmgbuild, which lays out the window (Pith, an arrow,
  Applications, a line on Open Anyway) without opening Finder. `make publish` puts it at a fixed address, `Pith.dmg`.
- One line in Terminal, the landing page's main action: `site/install.sh` downloads Pith.dmg with curl (so nothing is
  quarantined), mounts it hidden, refuses a Pith not signed with the local certificate, stops a copy already there and
  its waiting update, and opens the new one from /Applications (~/Applications if that isn't writable).
- The landing page's setup: the Terminal line, then the installer's four steps, how a setting changes and how updates
  arrive.
- A blank icon on the notifications was macOS's icon cache, from before Pith had an icon (AGENTS.md, Traps).
- FEATURES §11 keeps the one question left: asking each other permission only when its feature first needs it.

## 12. Bug check before friends

Status: **done**. Every source file, the install script, the Makefile and the landing page were read; 39
findings, each fixed with a test where one can run off screen, confirmed, or kept (26). Published in 0.3.8 to 0.3.11
(2026-11-23 and 24). On 2026-11-24 Edoardo removed Pith and installed 0.3.10 with the Terminal line, as a friend would:
no Open Anyway, the folder prompts with their reasons, Accessibility on the first paste, reopening Pith.app and Quick
Look closing on a click elsewhere all work. Another keyboard layout (16) is tested only on the Mac's own.
- **Critical:**
  1. A mistake in config.toml changes nothing it doesn't have to (decision 59), so a half-typed line can't drop
     clipboard history; curly quotes get their own problem.
- **High:**
  2. Opening the clipboard from the launcher checks Accessibility again.
  3. A thumbnail that can't be read is asked for once, not forever.
  4. Each protected folder is read on a worker of its own and joins the index once allowed (decision 60).
  5. A folder in `folders` is indexed even inside one the rules skip (`~/Library/CloudStorage`, `~/.config`).
- **Medium:**
  6. A copy landing while the clipboard is open keeps the selected clip selected.
  7. The keypad's Enter (and fn+Return) is Return.
  8. The tile and Quick Look follow a click; a click below the rows keeps the selection.
  9. A copy is read without images first; text and files keep no image (decision 61).
  10. With Quick Look up, a click in another app, or another app coming to the front, closes both; losing the
      keyboard to the preview doesn't (0.3.7 broke ⌘Y that way, fixed in 0.3.8).
  11. Hotkeys can move onto each other's keys or swap them.
  12. A clip with nothing left to put back fails with a notification and leaves the clipboard as it is.
  13. Open With…'s apps land only where they were chosen.
  14. Opening Pith.app while it runs opens the launcher.
  15. Overlapping folders are scanned once, and a configured folder that's created, moved or mounted is rebuilt.
  16. Hotkeys and the paste's ⌘V are on the key that types their letter in the layout in use (`KeyLayout`).
  17. Deleting tens of thousands of indexed files no longer stalls the main thread (421 ms → 0.4 ms), and a file
      search of more than 16 words finds nothing at once.
- **Low:**
  - The clipboard: (18) a picture copied from a text view is an image clip; (19) a long file list keeps about 2,500
    whole paths and counts them all; (20) pins don't count toward the size cap (decision 62); (21) the database is
    created in one transaction; (22) a copy whose notice comes after Clear stays gone; (23) a copy that changes while
    it's read is read again from the start.
  - The panel: (24) held down, only `up` and `down` repeat; (25) typing cancels a waiting second ⏎; (26) kept: Update
    Pith is selected when the empty state is otherwise empty; (27) a copied file's facts are read again each time the
    clipboard opens; (28) only ⏎ on a clip asks for Accessibility.
  - Files: (29) a case-only rename leaves no duplicate; (30) what was just opened is never the one forgotten; (31) at
    launch, only what's missing on a drive that's there is forgotten; (32) FSEvents leaves out up to 8 skipped folders
    in a root; (33) past 256 file types, closing the panel drops the least recently used icons.
  - Config: (34) a hotkey can't be an editing key; (35) `open` or `back` turned off keeps its default reserved; (36)
    a symlinked config.toml reloads when its target is saved; (37) only events for config.toml itself reload it;
    (38) FEATURES' examples match the settings.
  - Install: (39) the Terminal line removes a waiting Sparkle update before it replaces Pith.
- **After the check:** Quick Look's window took the keyboard, so ↓ and ⌘Y went to the app underneath, and a refreshed
  list could switch its file. The panel takes the keyboard back while the preview is up, and the preview keeps its
  file until the user moves (`PreviewTarget`). Published in 0.3.11.
- **Paste next** (decisions 63, 64): each ⌃⌥V pastes the next clip down the history from the newest, without the
  panel; a 10 s pause or a new copy starts over. `PasteRun` holds the order at the first press.

## 13. Ready for a critical reader

Status: **done**, before Pith is posted on Hacker News: the code, the docs, the memory target and checks before each
release; published in 0.3.12.
- **Code:** done. `LauncherViewController` (1,672 lines) is its state, the list and the selection, with one extension
  per concern beside it (the tile, the rows, ⌘K and opening, the clipboard, keys, Quick Look). `FileFacts`, `LinkApps`,
  `ClipPaster` and `DateWords` are small types of their own; `StageView` is `TileView`, as the docs call it;
  `Config.parse` reads through a `Parser`, one method per table; `FileIndex.search` scores each chunk in a function of
  its own over the pinned buffers; every `@unchecked Sendable` and force unwrap says why it's safe. No behavior change:
  97 + 144 tests pass (2 new, for `FileFacts` and `LinkApps`), the snapshots are unchanged, and `make bench` is within
  its run-to-run noise of the build before, measured side by side.
- **Docs:** done. The status lines say what's true now and what's left, and the narrative of fixed bugs is in git.
  README is for people using Pith and FEATURES the spec, without the same tables in both; every link and anchor
  resolves.
- **Release checks:** done. Quick Look sits behind a small `PreviewPanel` protocol, and the panel's visibility and
  its click monitor can be swapped, so `PanelFocusTests` runs the focus rules off screen with a fake preview: one
  press toggles it once, the arrows move it, losing the keyboard to it keeps the panel (0.3.7's ⌘Y), a click in
  another app or another app in front closes both, ⎋ closes it first. Reintroducing 0.3.7's bug or the double toggle
  fails them. `docs/RELEASING.md` has the checks on the installed build before each `make publish`.
- **Memory:** measured, not fixed. The installed 0.3.11, relaunched, one use at a time with `footprint` every 2 s and
  `heap` after each: 43 MB at launch; ⌘P and typing +7 MB (3 MB of heap the first time text is searched and drawn, the
  rest the panel's surfaces, kept for a one-frame ⌘P); ⌘⇧V +3 MB; the first Quick Look +10 MB (6 MB of heap for its own
  panel, which stays); paste, paste next and idle nothing; a screenshot copy a 6 MB peak. Scrolling a long PDF in Quick
  Look peaks at 121 MB, the spike seen before, and leaves 85–90 MB: its freed heap is scattered through pages still in
  use. About 8 MB of heap is AppKit's drawing caches, most of them for text, which any app holds once it draws. Tried on the installed build
  and reverted, neither measurably helping: giving freed pages back after the panel closes
  (`malloc_zone_pressure_relief`, at once or 5 s later), and Quick Look letting go of its file as it closes. Left:
  Quick Look's memory. Freeing it means a preview window of Pith's own, made and dropped per use, which looks and
  behaves differently from Quick Look's; Edoardo kept ⌘P and Quick Look as they are (decision 72), and step 8 closed
  over the target (decision 77).

## 14. The history in step with its database

Status: **done**, published in 0.3.13. Clips another program deleted from
`history.sqlite` stayed listed in the installed 0.3.12, so ⏎ and Copy to Clipboard failed on them with "it's no
longer in the history", and the list's order and times went stale.
- The history loads again as the clipboard opens when `PRAGMA data_version` says another connection committed
  (decision 73); a clip the store no longer has leaves the list as its paste, copy, move or save fails.
- ⎋ from a clip's ⌘K actions shows the list as it is now: copies that landed meanwhile used to wait for the next one.
- Delete from its shortcut waits for a second press (decision 74).
- 108 + 145 tests pass; each new one fails without its fix. The snapshots are unchanged.

## 15. Bug check of the app

Status: **done**, published in 0.3.14. Four readers went through every file of the app (`Sources/Launcher`), and
the clipboard's core beside it; each finding was checked against the code, and all were fixed, each with a test that
fails without its fix, except where noted. 129 + 148 tests pass; the snapshots are unchanged.
- **High:**
  1. A stricter clipboard limit applies only once it has stayed set for a minute (decision 76): an editor saving as
     you type could save `max_age_days = 3` on the way to 365 and prune everything older.
  2. A clip of thousands of files is read in one job and redraws the tile once; rows find the first path and the
     folders without splitting the list (it was seconds of main-thread work).
- **Medium:**
  3. The file index's folders are resolved on a worker: `realpath` on main could wait on a privacy prompt or a dead
     network share. No test: it would need the prompt.
  4. A copied folder keeps its `/`, so it shows as a folder; a folder's own size isn't shown.
  5. ⌘C then ⌘Tab names the app copied from, not the one that came to the front.
  6. Open Link opens a link longer than 4,096 characters whole.
  7. An image converted to PNG keeps its EXIF orientation (drawn upright) and its DPI.
  8. SQLite waits up to 2 s for another program's write, and a committed delete always leaves the list.
  9. A clip kept selected for a Pin or Delete is let go when the panel closes or the write fails.
  10. ⏎ or ⌘K before the query's files land runs on the query's list.
  11. Icons are drawn again when a sharper screen appears.
  12. A long link fits the tile's three lines whole, with "…" in its middle.
- **Low:**
  - The clipboard: (13) blank lines first don't make a text's preview "Spaces and line breaks"; (14) a list of more
    files than memory keeps counts them all and shows no partial size; (15) "Open in …" follows a new default
    browser, and `[open_links]`' app applies before its name is known; (16) a copy caught between an app's clear and
    its write is looked at again; (17) paste next waits until the app has read its clip (at most 500 ms), not a fixed
    100 ms; (18) a paste of a clip with no source doesn't take the target app's name.
  - The panel: (19) an emptied list closes Quick Look, and one that shrinks past the selection moves it; (20) ⌥⏎, ⌥⇥
    and ⌥⎋ don't type into the query; (21) dates in another year say it.
  - Icons: (22) Open With's apps outside the indexed folders get icons; (23) an app updated in place gets its new
    icon; (24) an app that isn't installed doesn't blink while another is looked up.
  - The app: (25) a config mistake at launch leaves Login Items alone; (26) a hotkey macOS uses (⌘Space) counts as
    taken; (27) a keyboard layout change registers all hotkeys again and updates the problems; (28) update
    notifications replace each other, and a scheduled check failing on the same update says it once; (29) System
    Settings opens without waiting on the main thread (no test); (30) the hotkeys don't wait for the opened-files
    history to check every file at launch.
