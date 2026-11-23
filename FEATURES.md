# Pith — Features

> The app is called **Pith** (decision 30): bundle ID `dev.edoardo.pith`, config in `~/.config/pith/`.

A minimal, keyboard-only macOS launcher + clipboard manager. Native Swift + AppKit. No AI, no extensions, no account, no telemetry. Opens in one frame.

---

## 1. Principles

- **Fast above all.** Always resident, window pre-built, indexes in memory. Nothing touches disk or network while you type.
- **Keyboard only.** Everything reachable without the mouse.
- **Small scope.** Launcher, clipboard, calculator. Nothing else.
- **Mac only.** macOS 26 Tahoe+, Apple Silicon.

### Performance targets

| Metric | Target |
|---|---|
| Hotkey → window visible | ≤ 1 frame (~16 ms) |
| Keystroke → results updated | < 5 ms |
| Idle CPU | ~0% |
| Idle RAM | < 50 MB |

---

## 2. Window

- Floating, non-activating panel, **centered on the active screen, fixed size**.
- Light/dark follows the system.
- `Esc` closes (or goes back one level when inside a sub-view such as actions or the editor).
- Closes automatically when it loses focus.
- **No Dock icon, no menu bar icon.** App-level commands live in the launcher (see §7).
- Launches at login.

---

## 3. Keyboard

### Global hotkeys

| Key | Action |
|---|---|
| `⌘P` | Open launcher (always global, no per-app pass-through) |
| `⌘⇧V` *(default, configurable)* | Open directly in clipboard mode |

### Inside the window

| Key | Action |
|---|---|
| `↑` / `↓`, `Ctrl+K` / `Ctrl+J` | Move selection up / down |
| `Enter` | Primary action on selected item |
| `⌘K` | Open actions panel for selected item |
| `⌘Q`, `⌘W`, `⌘E`, `⌘R`, `⌘T`, `⌘Y`, `⌘U` | In the actions panel: run its 1st to 7th action (decision 43) |
| `Esc` | Back / close |

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

- Indexed from a **configured list of folders** only (e.g. `~/Desktop`, `~/Documents`, `~/dev`).
- Skips noise: `.git`, `node_modules`, `.build`, caches, hidden files (configurable ignore patterns).
- Kept fresh via FSEvents; index lives in memory.

| Key | Action |
|---|---|
| `Enter` | Open with the app set for its type in `[open_with]`, else the default app |
| `⌘K` → Reveal in Finder | |
| `⌘K` → Copy path | Full POSIX path to clipboard |
| `⌘K` → Open with… | Pick an app |
| `⌘K` → Quick Look | Preview without opening (also `Space` / `⌘Y`) |
| `⌘K` → Copy file | Puts the file itself on the clipboard (paste in Finder, Slack, …) |
| `⌘K` → Zip | See §4.4 |
| `⌘K` → Move to Trash | |

### 4.3 Folders

| Key | Action |
|---|---|
| `Enter` | Open in Finder |
| `⌘K` → Copy path | |
| `⌘K` → Open in terminal | Terminal app is configurable (Terminal, iTerm2, Ghostty, Warp, …) |
| `⌘K` → Zip | See §4.4 |
| `⌘K` → Copy folder / Move to Trash | Same as files |

### 4.4 Zip

- Uses macOS's own tool: `ditto -c -k --sequesterRsrc --keepParent` (same as Finder's *Compress*).
- Output next to the source as `name.zip` (`name 2.zip` if it exists).
- Runs in the background; window can close. Notification / indicator on completion.
- If `ditto` proves too slow on large folders, evaluate alternatives later.

---

## 5. Clipboard

### 5.1 Recording

- Polls the system pasteboard (`changeCount`) in the background.
- Records **everything**: plain text, rich text, images, files, URLs.
- **Skips concealed copies**, which password managers mark (decision 35), and transient or auto-generated ones (decision 38). Everything else is recorded. Recording pauses from the launcher (decision 44). *(Revisit: ignore-app list.)*
- Stored locally in SQLite; images stored as files with thumbnails.
- Screenshots: set macOS to save screenshots to the clipboard (`⌘⇧5` → Options → Save to → Clipboard, or use `⌘⌃⇧4`). They then land in history automatically. **No code needed.**

### 5.2 Retention

Both limits apply; whichever triggers first wins:

- **Size cap** in GB (2 GB by default, decision 37) — oldest dropped first.
- **Max age** in days (30 by default) — older items deleted.
- **Pinned items are never dropped.**

### 5.3 Browsing

- Opened via `⌘⇧V` or the `c ` prefix.
- List with preview pane (text, image, file info, URL).
- Newest first. Pinned items are found by typing: pinned matches come first (decision 33).
- **Search** over text content and file names.

### 5.4 Actions

| Key | Action |
|---|---|
| `Enter` | **Paste into previous app** (window closes, item pasted at cursor; needs Accessibility permission) |
| `⌘K` → Copy to clipboard | Moves item to the top of history and onto the clipboard, so a normal `⌘V` pastes it |
| `⌘K` → Paste as plain text | Strip formatting |
| `⌘K` → Pin / Unpin | |
| `⌘K` → Delete | |
| `⌘K` → Edit text | *After milestone 3 (decision 36).* In-panel editor; saving creates a new entry at the top and puts it on the clipboard (original kept) |
| `⌘K` → Edit image | *After milestone 3 (decision 40).* Opens in Preview; when saved, the edited image comes back as a new entry at the top |
| `⌘K` → Save as file | Images / text to a file in Downloads, then a notification (decision 39) |
| `⌘K` → Open URL | For copied links, with the app set for the scheme in `[open_links]`, else the default |
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

Single file, no settings window: `~/.config/pith/config.toml`. Reloaded automatically on save.

```toml
[hotkeys]
launcher  = "cmd+p"
clipboard = "cmd+shift+v"

[launcher]
empty_state = "recent"   # recent | running | none
launch_at_login = true
folders = ["~/Desktop", "~/Documents", "~/Downloads", "~/dev"]
ignore  = [".git", "node_modules", ".build", "*.photoslibrary"]
max_depth = 6

[actions]
terminal = "Ghostty"   # Terminal | iTerm | Ghostty | Warp | …

# Which app opens what, for files and links opened from the launcher (macOS defaults are untouched).
[open_with]            # file extension or type → app (name, bundle id or path)
md  = "Visual Studio Code"
pdf = "Preview"
"public.image" = "Pixelmator Pro"

[open_links]           # URL scheme → app
https  = "Safari"
mailto = "Mail"

[clipboard]
max_size_gb = 2
max_age_days = 30

[calculator]
currency_refresh_hours = 24
```

---

## 9. Out of scope

AI of any kind · extensions / store · snippets · quicklinks · window management · emoji picker · translate · calendar · notes · focus · hyper key · script commands · themes · cloud sync · accounts.

---

## 10. Tech notes

- Swift Package, AppKit (`NSPanel` + `NSTableView`, view reuse). SwiftUI not used in the hot path.
- `LSUIElement` (no Dock icon), `SMAppService` for launch at login.
- Global hotkeys: Carbon `RegisterEventHotKey`.
- Storage: SQLite (the system library). Config: TOML (our own reader).
- Updates: Sparkle, the one dependency, from `pith.edoardobertoli.xyz` (decision 48).
- Paste: `CGEvent` ⌘V into the previously active app → requires **Accessibility** permission.
- Icons loaded lazily, cached in `NSCache`.
- Always build/profile in Release.

---

## 11. Open questions

- [x] **Pick a final name:** Pith (decision 30)
- [x] Clipboard hotkey: `⌘⇧V` (decision 34)
- [ ] Clipboard privacy: concealed copies are skipped (decision 35) and recording pauses from the launcher (decision 44); an ignore-app list?
- [ ] Every keybind configurable in `config.toml` (Edoardo, 2026-11-23, the next task): today only `[hotkeys] launcher` and `clipboard` are; the panel's keys (§3: ↑ ↓ ⌃K ⌃J, ⏎, ⌘K, ⌘Q–⌘U, ⎋, Space and ⌘Y, ⌫, the `c ` prefix) are fixed.
- [ ] Paste down the history by repeating a key (Edoardo, 2026-11-23, after the keybinds). Two readings to settle with
  him: (a) cycle, like ⌘Tab: hold ⌘⇧, each V moves the selection one item down, letting go pastes it (Flycut and
  Jumpcut work this way; today a second ⌘⇧V closes the panel, so that would change, and esc would still close); (b) a
  paste stack: each press pastes the next item without showing the panel, for filling forms. Claude recommends (a): it
  shows what will be pasted, and a quick ⌘⇧V still just opens the panel. Its key joins the configurable keys.
- [ ] A first install and updates that follow macOS's conventions, with as few privacy prompts as possible (Edoardo,
  2026-11-23, after the keybinds). Without the paid Apple Developer Program (decision 46) Pith can't be notarized, so
  the first open always needs Open Anyway; everything else is open. To check, then propose: the prompts a new user
  gets today and when (Desktop, Documents and Downloads on the first scan of `~`, Accessibility on the first paste,
  clipboard access, notifications, the login item), asking each one only when its feature first needs it with a line
  saying why, and whether a Homebrew cask in a tap of Edoardo's is worth adding beside the zip.
- [x] Default size cap / max age: 2 GB, 30 days (decision 37)
