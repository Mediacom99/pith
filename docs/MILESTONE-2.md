# Milestone 2: files and folders

Goal: the launcher finds any file or folder in the configured folders (by default your whole home folder) as fast as
it finds apps, and acts on it from the keyboard: open (in the app set per type), reveal, copy, preview, zip, trash,
open in a terminal (`FEATURES.md` §4.2–4.4, decisions 15, 18–22). Same targets: keystroke → results under 5 ms, idle
means idle, memory well under 50 MB.

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. File index

Status: **done** (core library; the app uses it from step 2).
- `FileScanner` walks the roots with `fts` (physical, no stat, never crossing volumes) and reads names straight from
  it. Packages count as files.
- `IgnoreRules` covers names (`node_modules`), prefixes and suffixes (`.*`, `*.photoslibrary`), globs, and paths
  (`~/Library`).
- `FileIndex` is a tree in flat arrays: names, parents, depths, flags, keys in a `KeyStore`, plus an O(1) lookup by
  (parent, name hash). Paths are rebuilt only for results.
- Your home folder with the defaults: 35,627 entries, a 130–150 ms scan (warm cache) and 4.4 MB; 100k files take
  16 MB. A search takes 0.1–0.3 ms, spread over the cores.
- Covered by 17 tests: ignore rules, scanning real temporary folder trees, the tree's lookup, removal, compaction,
  boosts, and the engine.

## 2. Search across apps and files

Status: **in review**.
- Each keystroke searches the apps synchronously and the files on the file engine's queue, then shows one list.
  Apps get a +24 head start (decision 19), and the history boosts both.
- The settings `folders`, `ignore` and `max_depth` (from step 4) set what's indexed; changing them rebuilds the
  index.
- File rows show the name, then the folder (`~/…`, cut from the start when long), with icons per type (folder, per
  extension, an app's own) rendered on first sight off the main thread.
- `recent` lists files and folders too; deleted ones are dropped from the history when it loads.
- Opening a file uses its default app (`[open_with]` comes in step 5), and a folder opens in Finder.
- ⌘K on a file offers Open and Reveal for now. Leaving ⌘K restores the results and selection without searching
  again.
- The table never rebuilds its cells: results reconfigure the cells on screen, and an empty list only hides them.
  That took per-keystroke work from 3.8 ms to 1.5 ms (apps + 35.6k files, offscreen), and showing the panel from
  1.7 ms to 0.3 ms.

Covered by UI tests: merged results with folder detail, apps first on equal matches, files in `recent`, file actions.
Waiting for Edoardo's run.

## 3. Live updates

Status: **in review**.
- The engine owns an FSEvents stream with per-file events on its roots, delivered straight onto its queue, with the
  ignore list's paths (`~/Library`) excluded at the source.
- An event under a folder that isn't indexed (hidden, ignored, too deep) is dropped with a hash lookup and no
  file-system call. Otherwise one `lstat` decides whether to add, update or remove, so repeated and out-of-order
  events are harmless.
- A folder that appears is scanned with its contents; dropped events trigger a rescan of that subtree. Events during
  a rebuild are buffered and replayed.
- Roots are resolved with `realpath`, because FSEvents reports real paths. Deleted files and folders are also dropped
  from the history.
- Covered by tests on real FSEvents: new files, folders moved in, deletions and renames (each picked up within about
  1 s), and ignored or too-deep items kept out.

## 4. Config

Status: **in review**.
- `folders`, `ignore`, `max_depth`, `[actions] terminal` and `[open_with]` are parsed, documented in the template
  and tested.
- App names resolve by name (as listed, or the file name, any case), bundle id or path, on a worker, once the index
  knows the installed apps.
- An unknown app or type becomes a problem row: `open_with.md: no app "…"`, `actions.terminal: no app "…"`.

## 5. File and folder actions (features 12, 14)

Status: **in review**.
- ⏎ opens a file in its `[open_with]` app: by extension, else the most specific matching type (`public.png` before
  `public.image`), else the default app. A folder opens in Finder.
- ⌘K on a file: Open, Reveal in Finder, Copy Path, Open With…, Copy File, Move to Trash.
- ⌘K on a folder: Open in Finder, Reveal in Finder, Copy Path, Open in Terminal (the `terminal` app), Copy Folder,
  Move to Trash.
- Open With… lists the apps LaunchServices offers for the file, filterable; ⏎ opens it with the chosen app.
- ⎋ steps back one level as it was, and ⌘K goes back to the search.
- Copying, revealing and trashing run on a worker. Trash asks no confirmation, since it's reversible.
- Covered by tests: the resolver against real apps, type matching, action lists per kind, Open With… navigation. The
  clipboard and Trash actions aren't exercised, so tests never touch your clipboard or Trash.

## 6. Quick Look (feature 13)

Status: **in review**.
- ⌘Y, or Space with an empty search field (decision 20), toggles a Quick Look preview of the selected file or
  folder; the preview sits one level above the launcher.
- The keyboard stays with the launcher: ↑/↓ move through the results and the preview follows; a row that isn't a
  file closes it. After a click into the preview, ↑/↓ are forwarded back.
- ⎋ closes the preview before anything else. Dismissing the launcher closes it, and focus moving into the preview
  doesn't dismiss the launcher.
- Tested: which rows can be previewed. Not tested on screen, since a test would have to show the panel: that's for
  Edoardo's run.

## 7. Zip (feature 15)

Status: **in review**.
- ⌘K → Zip on a file or folder runs `ditto -c -k --sequesterRsrc --keepParent` on a worker, so the launcher closes
  right away.
- Names follow Finder: `report.pdf.zip`, `Folder.zip`, then `… 2.zip`.
- When it finishes, a notification reads "Zipped: name.zip", and clicking it reveals the zip; a failure says why.
  macOS asks for notification permission the first time, alongside the zip rather than before it; without
  permission the zip simply appears.
- Tested on real folders: the zip unpacks to the same contents, taken names are numbered, failures are reported. The
  notification isn't exercised in tests.

## 8. Performance pass

Status: **in progress**, waiting for an on-screen run of this build.
- The last run (milestone 1 build) measured ⌘P → drawn at 28–49 ms, nearly all "update", and keystrokes at 4–18 ms:
  delivery 1.4–11, update 0.1–6.5, draw 0.5–9.
- That build rebuilt the table's cells on every update and every show. Fixing it took the offscreen cost from
  3.8 ms to 1.5 ms per keystroke (with 35.6k files) and from 1.7 ms to 0.3 ms per show.
- Slow deliveries are mostly keys waiting behind the previous keystroke's drawing, so they should shrink too.
- Next: `make logs` and `make stats` on this build, then fix whatever phase is still over target (FEATURES §1: ⌘P
  within a frame, keystrokes under 5 ms).
