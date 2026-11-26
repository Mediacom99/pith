# Pith — Features

> The app is called **Pith** (decision 30): bundle ID `dev.edoardo.pith`, config in `~/.config/pith/`.

A minimal, keyboard-only macOS launcher + clipboard manager. Native Swift + AppKit. No AI, no extension store, no account, no telemetry. Opens in one frame.

---

## 1. Principles

- **Fast above all.** Always resident, panel pre-built, indexes in memory. Nothing touches disk or network while you type.
- **Keyboard only.** Everything reachable without the mouse.
- **Small scope.** Launcher, clipboard, calculator. Nothing else.
- **Mac only.** macOS 26 Tahoe+, Apple Silicon.

### Performance targets

| Metric | Target |
|---|---|
| Hotkey → panel visible | ≤ 1 frame (~16 ms) |
| Keystroke → results updated | < 5 ms |
| Idle CPU | ~0% |
| Idle RAM | < 50 MB |

---

## 2. The panel

- Floating, non-activating panel, **centered on the active screen, fixed size**.
- Light/dark follows the system.
- `Esc` closes (or goes back one level when inside a sub-view such as actions or the editor).
- Closes automatically when it loses focus.
- **No Dock icon, no menu bar icon.** App-level commands live in the launcher (see §7). Opening Pith.app while it runs
  opens the launcher, the way in when its hotkey doesn't fire.
- Launches at login.

---

## 3. Keyboard

Every key is a default that `[hotkeys]` and `[keys]` in the config change (§8, decision 55); the README's
[Keys](README.md#keys) and [Configuration](README.md#configuration) list them. The text editing keys of the search
field (`⌘X`, `⌘C`, `⌘V`, `⌘A`, `⌘Z`, `⇧⌘Z`) are fixed, and no hotkey can take them from every app.

- **Global hotkeys** (`[hotkeys]`): `launcher` opens the launcher (⌘P, always global, no per-app pass-through),
  `clipboard` opens the panel straight in the clipboard (⌘⇧V), and `paste_next` pastes down the history without
  opening anything (⌃⌥V, §5.4, decision 64). `""` turns the last two off.
- **Inside the panel** (`[keys]`): `up`, `down`, `open` (⏎: the primary action on the selected row), `actions` (⌘K),
  `back` (⎋: back one level, or close), `preview` (Quick Look, §4.2), `run_actions` (in an actions list, the 1st to
  7th action, decision 43) and `to_launcher` (⌫: from the clipboard back to the launcher, §5.3).

A key without ⌘, ⌥ or ⌃ that types (a letter, Space, ⌫) works only while the search field is empty.

---

## 4. Launcher (root search)

- **Empty state:** configurable (`[launcher] empty_state`): `recent` (default; what you opened last, newest first), `running` (open apps, most recently used first, then all other apps alphabetically) or `none` (just the search field).
- **Sources:** applications and files/folders from configured folders.
- **Matching:** fuzzy, word by word: every word must match, in any order. For files, earlier words may also match a folder in the path, so `acme/deploy` or `acme deploy` find `deploy.sh` under `Acme`.
- **Ranking:** match quality, boosted by frequency + recency of what you pick. Learns over time.
- **Calculator results** appear inline as the top row when the query parses as an expression (§6).
- **Prefix `c `** switches to clipboard mode, and the **Clipboard History** command (first for `c`, decision 42) opens it.

### 4.1 Applications

- Indexed from `/Applications`, `/System/Applications`, `~/Applications` (+ subfolders like `Utilities`).
- Running apps show a small indicator.

| Key | Action |
|---|---|
| `Enter` | Launch / bring to front |
| `⌘K` → Quit | Quit app (running only) |
| `⌘K` → Force Quit | Force quit (running only); asks for a second `Enter` in the row |
| `⌘K` → Reveal in Finder | |

### 4.2 Files

- Indexed from the **configured folders**: the home folder by default (decision 22), or a list (`~/Documents`, `~/dev`).
- Skips noise: `.git`, `node_modules`, `.build`, caches, hidden files (configurable ignore patterns). A configured
  folder is searched even inside one the patterns skip (Dropbox in `~/Library/CloudStorage`, `~/.config`).
- Kept fresh via FSEvents; index lives in memory.

| Key | Action |
|---|---|
| `Enter` | Open with the app set for its type in `[open_with]`, else the default app |
| `⌘K` → Reveal in Finder | |
| `⌘K` → Copy Path | Full POSIX path to clipboard |
| `⌘K` → Open With… | Pick an app |
| `⌘Y`, or `Space` with an empty field | Quick Look: preview without opening (decision 20) |
| `⌘K` → Copy File | Puts the file itself on the clipboard (paste in Finder, Slack, …) |
| `⌘K` → Zip | See §4.4 |
| `⌘K` → Move to Trash | |

### 4.3 Folders

| Key | Action |
|---|---|
| `Enter` | Open in Finder |
| `⌘K` → Copy Path | |
| `⌘K` → Open in Terminal | Terminal app is configurable (Terminal, iTerm2, Ghostty, Warp, …) |
| `⌘K` → Zip | See §4.4 |
| `⌘K` → Copy Folder / Move to Trash | Same as files |

### 4.4 Zip

- Uses macOS's own tool: `ditto -c -k --sequesterRsrc --keepParent` (same as Finder's *Compress*).
- Output next to the source as `name.zip` (`name 2.zip` if it exists).
- Runs in the background; the panel closes at once. A notification on completion.
- If `ditto` proves too slow on large folders, evaluate alternatives later.

---

## 5. Clipboard

### 5.1 Recording

- Polls the system pasteboard (`changeCount`) in the background.
- Records **everything**: plain text, rich text, images, files, URLs. A copy with text or files keeps only those, not the
  app's picture of them; one with neither is an image (decision 61).
- **Skips concealed copies**, which password managers mark (decision 35), and transient or auto-generated ones (decision 38). Everything else is recorded. Recording pauses from the launcher (decision 44). *(Revisit: ignore-app list.)*
- Stored locally in SQLite; images stored as files with thumbnails.
- Screenshots: set macOS to save screenshots to the clipboard (`⌘⇧5` → Options → Save to → Clipboard, or use `⌘⌃⇧4`). They then land in history automatically. **No code needed.**

### 5.2 Retention

Both limits apply; whichever triggers first wins:

- **Size cap** in GB (2 GB by default, decision 37) — oldest dropped first.
- **Max age** in days (30 by default) — older clips deleted.
- **Pinned clips are never dropped**, and don't count toward the size cap (decision 62).

### 5.3 Browsing

- Opened via `⌘⇧V` or the `c ` prefix.
- A list under the tile, which previews the selected clip (a text, an image, file info, a link).
- Newest first. Pinned clips are found by typing: pinned matches come first (decision 33).
- **Search** over text content and file names.

### 5.4 Actions

| Key | Action |
|---|---|
| `Enter` | **Paste into previous app** (the panel closes, the clip is pasted at the cursor; needs Accessibility permission) |
| `⌃⌥V` (paste next, any app) | Pastes the last clip copied, then at each press the one before it, down the history, without opening the panel. A 10 s pause or a new copy starts again from the newest; past the oldest, a press does nothing. Its pastes don't reorder the history (decisions 63, 64) |
| `⌘K` → Copy to Clipboard | Moves the clip to the top of the history and onto the clipboard, so a normal `⌘V` pastes it |
| `⌘K` → Paste as Plain Text | Strip formatting |
| `⌘K` → Pin / Unpin | |
| `⌘K` → Delete | At once from its row; a pinned clip, or Delete from its shortcut, waits for a second press (decisions 28, 74) |
| `⌘K` → Edit Text | *After milestone 3 (decision 36).* In-panel editor; saving creates a new clip at the top and puts it on the clipboard (original kept) |
| `⌘K` → Edit Image | *After milestone 3 (decision 40).* Opens in Preview; when saved, the edited image comes back as a new clip at the top |
| `⌘K` → Save as File | Images / text to a file in Downloads, then a notification (decision 39) |
| `⌘K` → Open Link | For copied links ("Open in Safari"), with the app set for the scheme in `[open_links]`, else the default |
| `⌘K` → Reveal in Finder | For copied files |

---

## 6. Calculator

Typed directly in the launcher; result shows as the top row. `Enter` **copies the result** and closes.

- **Math:** `+ - * / ^ %`, parentheses, `sqrt`, `sin`/`cos`/`tan`, `log`/`ln`, `pi`, `e`.
- **Units:** length, mass, volume, temperature, data size, time, speed — e.g. `5 km in mi`, `200 MB in GB`, `30 c in f`.
- **Currency:** e.g. `100 usd in eur`. Rates fetched once a day from a free source (e.g. ECB via frankfurter.app), cached on disk, last rates used offline. **This and the daily update check (decision 48) are the app's only network access.**
- **Programmer:** hex / binary / octal / decimal, bit ops — e.g. `0xff in bin`, `1 << 8`, `0b1010 & 0b0110`.

---

## 7. App commands (in the launcher)

Since there is no menu bar icon, these are searchable commands:

- **Clipboard History** — opens the clipboard in the panel; `c` alone lists it first (decision 42)
- **Open config** — opens `config.toml` in the default editor
- **Reload config** (also automatic on save)
- **Pause / resume clipboard recording**: only the one that applies is listed, and a pause lasts through a relaunch
  (decisions 44, 45)
- **Clear clipboard history** (keeps pinned, after a second ⏎)
- **Check for updates**: checks right away, and a notification says what it found (decision 50)
- **Update Pith**: listed once an update is downloaded; restarts into it (decisions 48, 49)
- **Quit Pith**

---

## 8. Configuration

Single file, no settings window: `~/.config/pith/config.toml`. Reloaded automatically on save. A mistake changes
nothing but shows up first in the launcher: a wrong value keeps its setting as it was, and a file that doesn't parse
keeps them all (decision 59).

Every setting, its default and what it does is in the README's [Configuration](README.md#configuration), and in
the commented template Pith writes on its first launch (`Config.template`). The tables: `[hotkeys]`, `[keys]` (§3,
decision 55), `[launcher]` (the empty state, `clipboard_alias`, launch at login, and the file index's `folders`,
`ignore` and `max_depth`, decision 22), `[clipboard]` (the limits, §5.2), `[actions]` (the terminal app), `[open_with]`
(file extension or type → app, decision 15) and `[open_links]` (URL scheme → app, decision 16). App names resolve by
name, bundle id or path; macOS's defaults are untouched. `[calculator]` comes with §6.

---

## 9. Out of scope

AI of any kind · an extension store · snippets · quicklinks · window management · emoji picker · translate · calendar · notes · focus · hyper key · themes · cloud sync · accounts. Anything else people want, they add themselves with Lua scripting, later (§12).

---

## 10. Tech notes

- Swift Package, AppKit (`NSPanel` + `NSTableView`, view reuse). No SwiftUI.
- `LSUIElement` (no Dock icon), `SMAppService` for launch at login.
- Global hotkeys: Carbon `RegisterEventHotKey`, on the key that types their letter in the keyboard layout in use.
- Storage: SQLite (the system library). Config: TOML (our own reader).
- Updates: Sparkle, the one dependency, from `pith.edoardobertoli.xyz` (decision 48).
- Paste: `CGEvent` ⌘V into the previously active app → requires **Accessibility** permission.
- Icons rendered off the main thread at their exact pixel size: the apps' at launch, a file type's the first time it
  shows.
- Always build/profile in Release.

---

## 11. Open questions

- [x] **Pick a final name:** Pith (decision 30)
- [x] Clipboard hotkey: `⌘⇧V` (decision 34)
- [ ] Clipboard privacy: concealed copies are skipped (decision 35) and recording pauses from the launcher (decision 44); an ignore-app list?
- [x] Every keybind configurable in `config.toml`: a `[keys]` table, and `[launcher] clipboard_alias` (decision 55)
- [x] Paste down the history by repeating a key: paste next on ⌃⌥V, from the last clip copied (decisions 63, 64)
- [ ] The other permission prompts a new user gets (Accessibility on the first paste, clipboard access,
  notifications, the login item): each asked only when its feature first needs it, with a line saying why. Done: the
  first install with one line in Terminal or a disk image (decisions 56, 57, 67), and the folder prompts, which say
  why and don't hold back the rest of the files (decision 60). Without the paid Apple Developer Program (decision 46)
  the disk image's first open needs Open Anyway; a Homebrew cask wouldn't avoid it.
- [x] Default size cap / max age: 2 GB, 30 days (decision 37)

---

## 12. Later: Lua scripting

*Planned, not scheduled (decision 70): after milestone 3, and designed when it starts.* The core stays small, fast and
minimal; users add what they want themselves, in Lua, through a small internal API, as Neovim, WezTerm, mpv and
Hammerspoon do.

- **Where:** one file of the user's, `~/.config/pith/init.lua` (beside `config.toml`), reloaded when it's saved. No
  store and nothing downloaded: scripts are the user's own.
- **A small first API**, to be settled at design time: commands in the launcher, ⌘K actions on files, apps and clips,
  hotkeys, and hooks on a copy (skip it, or change it).
- **It can't make typing slow:** anything a script adds while you type runs with a time limit (Lua stops a script
  after a set number of instructions) and under the same newest-wins rule as the file search; or the first API
  leaves out results-as-you-type, and has only commands and actions, which run when chosen.
- **Permissions:** a script runs with Pith's (Accessibility, the clipboard), so the docs say to run only scripts you
  trust.
- **Dependency:** Lua itself, vendored as C source (MIT, compatible with the GPL), the second dependency beside
  Sparkle.
- **Positioning:** "no extensions" becomes "no extension store" (done with decision 70); the README's Why and the
  landing page get a line about scripting when it ships.
