# Milestone 2: files and folders

Goal: the launcher finds any file or folder in the configured folders (by default your whole home folder) as fast as
it finds apps, and acts on it from the keyboard: open (in the app set per type), reveal, copy, preview, zip, trash,
open in a terminal (`FEATURES.md` §4.2–4.4, decisions 15, 18–22). Same targets: keystroke → results under 5 ms, idle
means idle, memory well under 50 MB.

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. File index

Status: **todo**.
- A scan with `fts` on a worker of the configured folders.
- Default folders: `~` (decision 22). Default ignore list: hidden files, `~/Library`, `node_modules`, `.build`,
  `*.photoslibrary`. Maximum depth 6.
- Packages such as bundles and libraries count as files, not folders. The scan never crosses into another volume, so
  mounts like ~/OrbStack are skipped.
- Names are stored contiguously (one byte buffer for all folded names), so 100k entries cost a few MB and no per-item
  allocations.

## 2. Search across apps and files

Status: **todo**.
- The file index has its own serial queue. Each search is spread over the cores and returns the top matches
  asynchronously, so the main thread never waits; a newer keystroke makes older searches skip.
- One ranked list with apps (decision 19), boosted by the history. Recently opened files show in `recent`.
- File rows show the name and the folder path.

## 3. Live updates

Status: **todo**. FSEvents with per-file events on the configured folders, with ~/Library excluded at the source.
Created, removed and renamed items are patched into the index on its queue. Dropped events trigger a rescan of that
subtree. No rescans of the whole tree.

## 4. Config

Status: **todo**. `[launcher] folders`, `ignore` and `max_depth`; `[actions] terminal`; `[open_with]` (extension or type →
app name, bundle id or path, decision 15). Problems show as rows, like the existing settings.

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
