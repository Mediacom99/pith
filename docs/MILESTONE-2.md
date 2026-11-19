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

Status: **in progress**. `folders`, `ignore`, `max_depth`, `terminal` and `[open_with]` are parsed, documented in
the template and tested. What's left is resolving `terminal` and `[open_with]` app names to apps, with problems for
unknown apps; that lands with the actions in step 5.

## 5. File and folder actions (features 12, 14)

Status: **todo**.
- ⏎ opens a file in its `[open_with]` app (else the default) and a folder in Finder.
- ⌘K offers Reveal in Finder, Copy path, Open with… (a list of the apps that can open it), Copy file/folder (onto the
  clipboard for pasting in Finder, Slack…), Move to Trash (no confirmation: it's reversible from the Trash), and Open
  in terminal for folders.

## 6. Quick Look (feature 13)

Status: **todo**. ⌘Y, or Space with an empty field (decision 20), toggles a Quick Look preview of the selected file.
↑/↓ keep moving through the results while it's open.

## 7. Zip (feature 15)

Status: **todo**. `ditto -c -k --sequesterRsrc --keepParent` in the background, writing `name.zip` (or `name 2.zip`)
next to the original. A notification on completion; clicking it reveals the zip (decision 21).

## 8. Performance pass

Status: **todo**. Measure on screen with your real home folder against the targets, together with milestone 1 step 9.
