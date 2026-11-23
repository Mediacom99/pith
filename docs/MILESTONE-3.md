# Milestone 3: the clipboard

Goal: Pith keeps a history of what you copy and pastes any of it back from the keyboard: ⌘⇧V, a glance, ⏎ (decision
31). It records text, links, images and files, opens in one frame, searches in under 5 ms per keystroke, and stays
under 50 MB idle. The design is `docs/BRIEF-CLIPBOARD.md`. Two pieces of `FEATURES.md` §5 come later: the in-panel
text editor and Edit Image (decisions 36, 40).

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Storage and retention

Status: **done** (core library; the app uses it from step 2).
- `ClipboardStore` keeps the history in `~/Library/Application Support/pith/clipboard/`:
  - a SQLite database (the system library) holding the entries and their text;
  - images as files beside it;
  - thumbnails rendered once with ImageIO at their exact pixel sizes (40 px for rows, the preview box at 2x).
- Each entry records:
  - its kind (text, rich text, link, image, files);
  - the pasteboard types it came with (the standard ones, step 2), so a paste puts them all back;
  - the source app, the time, a pin, and its size.
- **Retention:**
  - 2 GB and 30 days by default (decision 37, `[clipboard]` since step 6), oldest unpinned first; pins are never
    dropped.
  - Applied after each copy, at launch and when the config changes the limits, so no timer is needed.
- Every call runs on the store's own serial queue, `launcher.clipboard`, so it's off the main thread and off Swift's
  cooperative pool. The main actor gets ready-made `Clip` values.
- In memory, a clip keeps only the first 4,096 characters of its text; the rest stays on disk for the paste.
- Duplicates are matched by a SHA-256 of the kind, every representation and the image.
- Deleting gives the space back to the disk: incremental vacuum for the database, and the image files are removed.
  On load, image files a crash left without their clip are removed too.
- Covered by 12 tests on temporary folders, never the real `~/Library/Application Support/pith/`:
  - newest-first loading;
  - duplicates moving to the top with their pin;
  - representations coming back in order;
  - thumbnail sizes, including a small image that isn't scaled up;
  - retention by age, then size, keeping pins;
  - delete, clear, relaunch, long text, and leftover files.

## 2. Recording

Status: **in review**. Built and tested on a private pasteboard. The installed app records from launch, but the
history can't be seen until step 4 shows it.
- **Watching:** `ClipboardRecorder` runs a GCD timer on its own queue, `launcher.clipboard.watch`, because macOS has
  no notification for a new copy.
  - Every 0.5 s it reads the pasteboard's change count, with 0.25 s of leeway so the system can coalesce wakeups.
  - It stops while the screens sleep or another user's session is in front. Step 8 measures what it costs at idle.
  - What's on the clipboard at launch isn't recorded, so starting Pith never reads the clipboard by itself. `start()`
    returns once it has read the change count, so a copy made right after launch can't be taken for the old one.
- **Clipboard permission:** macOS can ask before an app reads the clipboard (`accessBehavior`, since 15.4).
  - "Ask" (or never asked yet): the copy is read, and macOS may ask Edoardo the first time.
  - "Never": nothing is read, and the log says so once. Step 4 shows it in the panel.
- **Skipped:** copies with a concealed, transient or auto-generated marker (decisions 35, 38). Only the types are
  read for this check, so a password's data is never fetched.
- **What's read:** only the standard types apps paste with:
  - plain text (UTF-8, UTF-16);
  - rich text (RTF, RTFD, HTML);
  - links (`public.url` and its title);
  - file URLs;
  - images (PNG, TIFF, JPEG, HEIC).

  Other types aren't read at all, because reading one makes the app that copied render it, and apps like
  spreadsheets offer many large ones. Pasting puts back the standard types, not an app's private format.
- **Classifying** (`ClipReading`, core library):
  - files win over everything, since Finder's copies also carry the name as text and the icon as an image;
  - an image counts only without text (screenshots, Copy Image), and is converted to PNG unless it already is one;
  - text that is one URL (http, https, mailto, ftp, ssh…) is a link;
  - text with RTF or HTML is rich text, and rich text with no plain text gets the pasteboard's conversion;
  - a copy with none of these is skipped.
- **Source:** the app named by the copy's `org.nspasteboard.source` marker, otherwise the app in front.
- **Duplicates:** a copy that is already in the history moves that clip to the top, keeping its pin. An unknown
  source doesn't overwrite a known one, so pasting from the history won't record "from Pith".
- **Old history** is pruned to `[clipboard]`'s limits at launch and after each copy (step 6).
- **Tests:**
  - 10 on classifying.
  - 6 on the recorder, on a private named pasteboard, so they never read or change your clipboard. They cover:
    source; nothing at launch; passwords and temporary copies skipped; files, images and links; RTF-only text; a
    paste from the history moving instead of duplicating.

## 3. History in memory and search

Status: **done** (core library and the app's model; the panel shows it from step 4).
- `ClipboardIndex` (core library) holds the clips newest first, each with a search key prepared when it arrives.
  - A text, rich text or link is searched by its text.
  - Files are searched by their names, not their folders.
  - An image has no text to search.
- **Matching:** every word of the query must appear in the clip as written, in any order, ignoring case and accents.
  - This isn't the launcher's fuzzy matcher. In a 4,096-character text, the letters of almost any short query appear
    in order somewhere, and scoring thousands of long texts per keystroke is too slow.
  - Keys and queries are folded the same way, in one Foundation call per text, plus a fast path for ASCII.
  - A 64-bit mask of the bytes present rejects most non-matches at once; `memmem` checks the rest.
- **Order:** newest first. When you type, pinned matches come first (decision 33). A pin older than the first 100
  matches is still found.
- **Scanning:** the newest clips are scanned first, and most queries fill the list there. Otherwise the rest is split
  over the cores, and the results are joined in order.
- `ClipboardIndex.matchingLine` gives the first line that matches, for a text row (step 4).
- **The app:** `ClipboardHistory` loads the history at launch and builds the index on a worker. The recorder starts
  only after that, so no copy lands in between. Each recorded copy and each clip retention drops updates it.
- **Speed** (`make bench`, release, 5,000 clips, limit 100):
  - **A typical month** (70 % short, 25 % medium, 5 % at the 4,096-character cap):
    - query as you type it: 0.01–0.04 ms per keystroke;
    - a word that matches nothing, scanning everything: 1.1–1.5 ms;
    - building the index: 27 ms on a worker.
  - **Worst case** (every clip at the cap, 20 MB of text):
    - typing: 0.05–0.34 ms;
    - matching nothing: 2.4–2.5 ms (12.9 ms before the scan was split over the cores);
    - building the index: 186 ms (680 ms with the launcher's per-character folding).
- Covered by 6 tests:
  - the empty query's order;
  - pins first, even past the limit;
  - any order, case and accents;
  - files by name, images without text;
  - inserting, re-copying, removing, pinning;
  - the matching line.

## 4. Clipboard mode in the panel

Status: **in review**. Built from the brief (§3, §5, §7) and checked on the `clipboard-*` snapshots in
`docs/snapshots/`, light and dark. ⏎ pastes since step 5.
- **Built:**
  - `LauncherViewController.Mode` (launcher or clipboard) on the same panel.
  - `[hotkeys] clipboard` (⌘⇧V by default) is registered like the launcher's. A taken hotkey becomes a problem row.
  - Each hotkey opens the panel in its mode, closes it in its own mode, and switches it from the other.
  - Rows per kind: `ClipText` gives the words, `ClipImages` the thumbnails, decoded on a worker, with the 12 newest
    clips' ready ahead of time. `IconStore` finds a source app by bundle id on a worker, and shows the kind's
    symbol only once the app is known to be missing, so a row never flips from symbol to icon.
  - The tile in the clipboard (`StageView.Preview`): a text in SF Mono, an image in its box on a checkerboard, a link
    or files as items.
  - A file's existence and size are read on a worker.
  - A long URL wraps over three lines and is cut in the middle past them.
  - States: the empty history (the tile alone), "Pith can't read the clipboard" in orange with ⏎ opening Privacy &
    Security (from step 2's permission check), and "Recording is paused" (step 6).
  - Quick Look (⌘Y, Space) previews an image or the first file.
  - The launcher's Clipboard History command (decision 42): "c" alone lists it first through its alias, its tile
    says "Also ⇧⌘V, from any app", and ⏎ opens the clipboard in place.
- **Small departures from the brief:**
  - Dates read "Oct 31", as the launcher's "opened Oct 31" does, rather than "31 Oct".
  - Sizes follow the Mac's region format, as Finder's do.
- **Speed** (`make bench`, release, in-process, 1,000 clips): showing the clipboard 1.0–1.1 ms (the launcher's recent
  list: 0.3 ms); a keystroke 0.09 ms to update. On screen in step 8.
- **Tests:** 11 tests, real panels never put on screen, ⏎ swapped out so they never touch the clipboard:
  - newest first under the 188 pt tile, and five whole rows;
  - pins first when typing;
  - a search with no match is only the bar;
  - the empty history shows the tile alone;
  - `c ` and ⌫ switch modes;
  - ⏎ takes the selected clip;
  - notices come first, but the newest clip is selected;
  - reset goes back to the launcher;
  - each kind's words;
  - the ages.
- **Opening it:**
  - ⌘⇧V (`[hotkeys] clipboard`, decision 34) opens it, switches to it, or closes it;
  - `c ` as the whole query switches to it from the launcher;
  - ⌫ on the empty field goes back to the launcher.
- **What changes:** the clipboard symbol and "Search clipboard" in the bar, and the 188 pt tile as the preview.
  - Text shows in SF Mono.
  - Images fit their box.
  - Links and files use the launcher's tile layout.
- **Rows** are drawn per kind, with ages and pins.
- **States:** empty history and recording paused.
- **Speed:** the newest rows and previews are ready in memory, so ⌘⇧V draws without touching the disk.
- **Snapshots:** every kind and state, light and dark, with AA contrast measured on them.

## 5. Paste and the ⌘K actions

Status: **in review**. Built and tested; paste itself, which types into another app, needs Edoardo's run. Three new
snapshots: `clipboard-actions`, `clipboard-delete-pinned`, `clipboard-accessibility`.
- **Built:**
  - ⏎ pastes, or copies without Accessibility access and asks for it once per launch.
  - Access is checked on a worker at launch and on each ⌘⇧V, since it can be given in System Settings at any time.
  - Without access, the notice "Paste needs Accessibility access" comes first, and ⏎ on it opens the setting.
  - A paste writes everything the clip was copied with, naming its source app (`org.nspasteboard.source`), so the
    recorder moves the clip to the top instead of recording it again.
  - Paste as Plain Text writes the text alone, marked transient so the history skips it, and moves the clip to the
    top itself.
  - Pin and Delete keep the panel open, go back to the list and keep the clip, or its place, selected.
  - Open in… names the app (`[open_links]`'s, else the default), looked up on a worker.
  - Save as File writes `Clipboard 2026-11-23 at 14.05.txt` or `.png` in Downloads, numbered when taken, then posts
    "Saved to Downloads".
  - Reveal says when the files are gone.
  - Failures post a notification (decision 32).
  - Force Quit's second ⏎ is now a general one (`confirming`).
  - In any ⌘K actions list, ⌘Q…⌘U run the 1st to 7th action, fixed per action, each row showing its letter
    (decision 43). A filter that hides the action is cleared, and a second press confirms.
- **Signing:** `make certificate` creates the "Pith Local Signing" certificate once (decision 41), and `make app`
  signs with it when it's there. Edoardo runs it, since macOS asks for his password.
- Tests cover which actions each kind gets, ⏎ pasting or copying, pin, delete's second ⏎ and Save as File, with
  delivery swapped out, so tests never type into your apps or touch the clipboard.

## 6. Commands and config

Status: **in review**. Built and tested; the commands and settings need Edoardo's run. Two new snapshots:
`clipboard-paused` and `clear-clipboard`.
- **Launcher commands** (`[hotkeys] clipboard` and Clipboard History landed in step 4):
  - Pause Clipboard Recording and Resume Clipboard Recording. Only the one that applies is listed (decision 45).
    - Paused, the recorder's timer is off, so pausing costs no wakeups. Resuming reads the change count first, so
      what was copied meanwhile is never recorded.
    - The pause is saved as a `paused` file in the clipboard folder and lasts through a relaunch (decision 44).
    - The clipboard lists "Recording is paused" first, quiet, and ⏎ on it resumes in place.
  - Clear Clipboard History asks for a second ⏎ in red, as Force Quit does, and its tile says "Pinned items stay".
    A failure posts a notification (decision 32).
- **Config:**
  - `[clipboard] max_size_gb` (more than 0 and at most 1000, decimals too) and `max_age_days` (1 to 3650), 2 and 30
    by default.
    - `ClipboardHistory` owns the limits: it prunes after the load, after each copy, and at once when the config
      changes them.
    - Nothing is pruned before the config is read, so a longer limit never loses clips at launch.
  - `[open_links]`: URL scheme → app, resolved like `[open_with]`.
    - `https` covers `http` unless `http` has its own.
    - `"https:"` or `"https://"` as a key means `https`.
  - Each is in the template, and a wrong value, or an app that isn't found, is a problem row.
- **Tests:** 10 new:
  - the limits and link apps parsed, and their problems;
  - a pause saved across a relaunch;
  - nothing copied while paused is recorded, even after resuming;
  - retention pruning when the limits are set and after a copy, keeping pins;
  - Clear keeping pins;
  - Clear's second ⏎, cancelled by ⎋;
  - only the recording command that applies, in the results and the recent list;
  - ⏎ on the paused row resuming in place;
  - `https` covering `http`.

## 7. Updates

Status: **done** (Edoardo, 2026-11-23). Built and tested (decisions 48–50). On Edoardo's Mac on 2026-11-23:
- 0.3.0 → 0.3.1 downloaded 11 s after the panel closed, and ⏎ to 0.3.1 running took under a second.
- 0.3.2 → 0.3.3: macOS presented "Pith updated to 0.3.3" 0.4 s after the restart (in the log; Edoardo didn't
  catch the banner), and Check for Updates then said "Pith is up to date".
- `Updater` wraps Sparkle 2.10.1, the one dependency:
  - Sparkle's schedule is off. Pith checks after the panel closes, at most once a day (an hour after a check that
    failed), and Sparkle starts only then, so nothing is read at launch and there's no timer.
  - A found update downloads in the background, is checked against the key in Info.plist and against the app's own
    signature, then waits.
  - The launcher lists Update Pith above the recent items, not selected, and search finds it; ⏎ installs and
    relaunches. Otherwise Sparkle installs it when Pith quits.
  - Only a copy in an Applications folder updates, so `make run`'s build is never replaced.
  - How it went is a notification (decision 49). The update that's ready is saved in Pith's defaults; the next launch
    reads it on a worker and says "Pith updated to 0.3.1" if it runs that build, or "Couldn't update Pith to 0.3.1"
    if Update Pith was chosen and it doesn't. A found update that fails to download, verify or install says so at
    once and is dropped, for the next check to find again. A check that can't reach the site stays quiet.
  - Check for Updates (decision 50) checks right away and always reports: "Pith 0.3.3 is ready", "Pith is up to
    date", or "Couldn't check for updates" with the reason beneath Sparkle's. The next scheduled check is a day after
    it. It's listed only where `Updater.isEnabled`, and not while an update is ready.
- **Make targets:**
  - `make app` embeds Sparkle's framework (2.9 MB, so the app is 4.9 MB) and signs it from the inside out with the
    app.
  - `make update-key`, once, creates Pith's own signing key in the login keychain and writes its public half into
    Info.plist.
  - `make publish` packages and tags the build, writes `appcast.xml` signed with the key, and deploys it to
    `pith.edoardobertoli.xyz` with `Pith-<version>.zip` and `Pith.zip`, the newest at a fixed address for a first
    install.
- **Tests:** the update row (first, not selected, ⏎ restarts, hidden until ready), the schedule (daily, an hour after
  a failure, a day after a check that was asked for), Check for Updates (listed only when it can do something), what
  the launch after an update reports, which errors are reported, each notification's words, and Info.plist keeping
  Sparkle's schedule off with downloads on. Snapshot: `update-ready`.

## 8. Performance

Status: **todo**. Measured with a month-sized history (thousands of entries, a few hundred screenshots), and Sparkle
in the build:
- ⌘⇧V → drawn;
- keystroke → drawn;
- idle CPU and wakeups with the recording timer;
- memory and threads (`make stats`).

The numbers go in this status line.

## 9. Design review

Status: **todo**.
- An impeccable critique and polish of clipboard mode against the brief, on the snapshots.
- `docs/DESIGN.md` is updated, through its full text, with:
  - the 188 pt tile;
  - the SF Mono preview;
  - orange for any setup problem.
- The values go in the Visual decisions table.

## 10. Configurable keys

Status: **in progress** (decision 55).
- **Core:**
  - `Shortcut` (was `Hotkey`) reads any key: `cmd+k`, `ctrl+j`, `up`, `space`. Whether it can be a global hotkey
    (cmd, ctrl or alt, or an F key) and whether it types are properties of it.
  - `Config` reads `[keys]` (a string or a list each) and `[launcher] clipboard_alias`, and `""` for a hotkey.
  - Problems: a value that isn't a key keeps the default; a key given twice, a hotkey's key or an editing key
    (⌘X C V A Z ⇧⌘Z) is left out of the later setting; `open` and `back` can't be empty.
- **The panel:** one lookup from the key pressed to what it does, in place of the fixed checks in `sendEvent`,
  `performKeyEquivalent` and the field editor's commands; Quick Look's ↑ ↓ too. A key that types acts only on an
  empty field. ⌘K lists check `run_actions` first.
- **What it shows:** the tile's keys (↩, Actions ⌘K, Back esc), the action rows' shortcuts, the selected row's ↩, and
  the Clipboard History tile's hotkey, from the config.
- **Docs:** the template, the README's keys and config, FEATURES §3 and §8, the landing page's #config section.
- **Tests:** parsing and every problem; the panel with keys rebound and turned off.
