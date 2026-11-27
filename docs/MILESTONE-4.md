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
- A type given two apps goes to its line of its own first, then to the earlier list; the line that loses is a problem
  in the launcher ("open_with sets "md" on line 6 too, so it opens in "Typora""). The same app twice is fine.
- A wrong value (`Zed = ["md", 3]`) keeps what that setting gave before, as any wrong setting does.
- Each app is looked up once: one that isn't installed is one problem, naming the types it was set for. Pith never
  checks whether such files exist.
- Open Config opens `config.toml` in the app `[open_with]` gives `toml`, else the default app for it, else TextEdit.
- The config template and the README's Configuration show both forms.

## 2. System Settings pages

Status: **in review**. 138 + 155 tests pass; each new one fails without its fix. On this Mac: 43 pages, read in 16 ms
at launch on a worker (Release).
- `SettingsScanner` reads the extensions in `/System/Library/ExtensionKit/Extensions` whose extension point is
  `com.apple.Settings.extension.ui` and that a link can open, limited to the ones System Settings lists: its
  `Sidebar*.plist` and General's `hosted_bundles` (without the sidebar file, every one that opens).
- **Names** come from each bundle's `InfoPlist.loctable` in the Mac's language, else its Info.plist. A page with
  several representations takes the one that applies: Battery or Energy by whether the Mac has a battery (IOKit), and
  other conditions are taken for the usual Mac (Mouse shows; Touch ID isn't hidden as it is for a guest). Its sidebar
  name and icon type come with it.
- Left out, since System Settings shows them only in cases Pith can't tell: FollowUps, Classroom, Class Progress, CDs &
  DVDs, Headphones, Game Controllers.
- A page is a result like an app: its icon (rendered once, with the apps'; Battery's from its type), its name, and
  "System Settings" where a file shows its folder. ⏎ opens `x-apple.systempreferences:<bundle id>`; ⌘K has nothing for
  it. No head start: an app that matches as well comes first. The history learns it, and `recent` lists it.
- Read the first time they're wanted and kept: they change only with macOS. `[launcher] system_settings = false`
  leaves them out, and changing it rebuilds the index.
- A snapshot, `settings-page`: "blue" finds Bluetooth.
- Found on the way: System Settings' own search reads `.searchTerms` files in each page, which name its sections and the
  anchors that open them (decision 79's note), a way to the deeper pages if Edoardo wants them.

## 3. Search by extension

Status: **in review**. 139 + 158 tests pass; each new one fails without its fix. The snapshots are unchanged.
- A query word like `*.pdf` (or `*.tar.gz`) keeps only files whose name ends with it, ignoring case and accents;
  folders, apps, commands and settings pages never match it (decision 80). `*.png *.jpg` takes either. The whole
  extension, as in a terminal: `*.pd` finds nothing. In the clipboard it stays a word like any other.
- Alone, those files come most recently changed first, up to the 50 rows. With other words (`budget *.pdf`), they
  rank as usual among those files.
- The dates live in the index: both ways were measured on the home folder (35,447 entries, Release). Reading them for
  the matches took 0.2 ms for 201 PDFs and 3.6 ms for 4,665 `.ts` files, close to the 5 ms budget. Keeping them costs
  4 bytes an entry (140 KB) and makes the scan about 3 % slower (126 → 130 ms), and the newest are then found in one
  pass. The scan `stat`s each entry (no more `FTS_NOSTAT`), and a change FSEvents reports updates its time.
- No snapshot of its own: the rows are ordinary file rows.

## 4. Paths with completion

Status: **in review**. 140 + 161 tests pass; each new one fails without its fix. The other snapshots are unchanged.
- A query that starts with `/` or `~/` is a path (decision 81, `PathQuery`). The list shows what's in the folder typed
  so far (up to the last `/`, `~` expanded, doubled slashes made one), narrowed to the names that start with the rest,
  ignoring case and accents, sorted as Finder sorts, up to the 50 rows. A link to a folder is a folder; a package (an
  app, a bundle) is a file, as in the index.
- Tab (`[keys] complete`, default `tab`) fills in the selected name, `~` kept as typed, and a folder gets its `/`, so
  its contents show next. Pressed before the folder is read, it waits for it, as ⏎ does. Outside a path it does
  nothing, as before.
- ⏎, ⌘K and ⌘Y act on the selected row as on any file or folder, and the history records it.
- The folder is read once on a worker (`FolderListing`), never the main thread; typing within it narrows that
  listing on the main thread, and a newer keystroke drops an older read. The listing is forgotten when the panel
  closes.
- Anywhere on the disk, not only the indexed folders, and the ignore patterns don't apply. Hidden names (a leading
  dot) show once the part after the last `/` starts with one. A folder that doesn't exist, or that macOS won't let
  Pith read, lists nothing.
- `acme deploy` (no leading `/` or `~/`) keeps the path words of decision 23.
- A snapshot, `path`: `~/Documents/ac` on a made-up folder. For step 5: each row repeats the folder that's typed.

## 5. Design review

Status: **todo**.
- `/impeccable critique` of the new rows on their snapshots, light and dark: a settings page, `*.pdf`, a path.
  Edoardo picks the fixes; `docs/DESIGN.md` takes in what's new.

## 6. Performance

Status: **todo**.
- `make bench` for a keystroke with an extension word, and in a path, over the full index; `make logs` and
  `make stats` on the installed build: the keystroke under 5 ms, memory after use, threads.
- The numbers go in this status line.
