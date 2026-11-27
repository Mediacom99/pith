# Milestone 4: better search

Goal: the launcher finds more, the way Edoardo asked for it (decision 78): System Settings' pages, files by their
extension (`*.pdf`), and paths completed as in a terminal; and `[open_with]` gives one app a list of extensions. Every
`FEATURES.md` §1 target still holds: ⌘P in one frame, a keystroke under 5 ms, nothing on the main thread waiting for
the disk. The calculator comes after, as milestone 5.

The new rows reuse the launcher's rows and tile (Stage, decision 29), so no design brief comes first; step 5 reviews
them.

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. `[open_with]` lists, and Open Config

Status: **in review**. 137 + 150 tests pass; each new one fails without its fix.
- In `[open_with]`, a list makes its key an app and its items extensions or types (decision 82):
  `"Visual Studio Code" = ["md", "txt", "json"]`. The one-line form stays: `md = "Visual Studio Code"`. Either form
  takes `md`, `.md` or `*.md`, in any case. An empty list sets nothing.
- A type given twice goes to its line of its own first, then to the earlier list; the line that loses is a problem
  in the launcher ("open_with sets "md" on line 6 too, so it opens in "Typora"").
- A wrong value (`Zed = ["md", 3]`) keeps what that setting gave before, as any wrong setting does.
- Each app is looked up once: one that isn't installed is one problem, naming the types it was set for. Pith never
  checks whether such files exist.
- Open Config opens `config.toml` in the app `[open_with]` gives `toml`, else the default app for it, else TextEdit.
- The config template and the README's Configuration show both forms.

## 2. System Settings pages

Status: **todo**.
- Read at launch, on a worker, with the apps: the extensions in `/System/Library/ExtensionKit/Extensions` whose
  extension point is `com.apple.Settings.extension.ui`, limited to the pages System Settings lists on this Mac (decision
  79). Each gives its name in the Mac's language, its icon, and its bundle id. Pages whose bundle has no shown name
  (Battery's reads "PowerPreferences") get System Settings' own; the step finds where it keeps it.
- A page is a launcher result, as an app is: its icon, its name, and "System Settings" where a file shows its folder.
  ⏎ opens it (`x-apple.systempreferences:<bundle id>`), off the main thread. The history learns it like anything else.
- No head start, as files: "dis" gives Discord before Displays until Displays is the habit.
- Icons are rendered once at their exact pixel sizes, with the apps'.
- `[launcher] system_settings = false` leaves them out; on by default.
- Not re-read while Pith runs: the folder changes only with a macOS update, which restarts the Mac.
- Tests: the reader over a temporary folder of made-up `.appex` bundles (the real file system), and the rows.
  A snapshot: "blue" finds Bluetooth.

## 3. Search by extension

Status: **todo**.
- A query word like `*.pdf` (or `*.tar.gz`) keeps only files whose name ends with it, ignoring case; folders, apps,
  commands and settings pages never match it (decision 80).
- Alone, it lists those files most recently changed first, up to the 50 rows. With other words (`budget *.pdf`), they
  search as usual among those files.
- Newest first needs each file's modification date: kept in the index (filled by the scan, which today skips `stat`,
  and kept fresh by FSEvents), or read for the matches only, on the file engine's queue. The step measures both and
  keeps the cheaper that stays under 5 ms.
- Tests: the query words, the filter and the order, on a temporary folder. A snapshot of `*.pdf`.

## 4. Paths with completion

Status: **todo**.
- A query that starts with `/` or `~/` is a path (decision 81). The list shows what's in the folder typed so far (up
  to the last `/`), narrowed to the names that start with the rest, ignoring case and accents, sorted as Finder sorts.
- Tab fills in the selected name, and a folder gets its `/`, so its contents show next. It's `[keys] complete`
  (default `tab`), and does nothing outside a path.
- ⏎, ⌘K and ⌘Y act on the selected row as on any file or folder.
- It reads the disk on the file engine's queue, never the main thread. Typing within one folder filters the listing
  already read; a newer keystroke drops an older read.
- Anywhere on the disk, not only the indexed folders, and the ignore patterns don't apply. Hidden names show once the
  part after the last `/` starts with a dot. A folder that doesn't exist, or that macOS won't let Pith read, lists
  nothing.
- `acme deploy` (no leading `/` or `~/`) keeps the path words of decision 23.
- Tests: splitting the query, the listing and its filter on a temporary folder, and Tab. A snapshot of `~/Pro`.

## 5. Design review

Status: **todo**.
- `/impeccable critique` of the new rows on their snapshots, light and dark: a settings page, `*.pdf`, a path.
  Edoardo picks the fixes; `docs/DESIGN.md` takes in what's new.

## 6. Performance

Status: **todo**.
- `make bench` for a keystroke with an extension word, and in a path, over the full index; `make logs` and
  `make stats` on the installed build: the keystroke under 5 ms, memory after use, threads.
- The numbers go in this status line.
