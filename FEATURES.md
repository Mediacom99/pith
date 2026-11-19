# launcher — Features

> **`launcher` is a temporary codename — rename to a cool name later.** It is used for the bundle ID (`dev.<you>.launcher`) and config path (`~/.config/launcher/`), so renaming is a find-and-replace.

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
| `Esc` | Back / close |

---

## 4. Launcher (root search)

- **Empty state:** nothing, just the search field.
- **Sources:** applications and files/folders from configured folders.
- **Matching:** fuzzy.
- **Ranking:** match quality, boosted by frequency + recency of what you pick. Learns over time.
- **Calculator results** appear inline as the top row when the query parses as an expression (§6).
- **Prefix `c `** switches to clipboard mode.

### 4.1 Applications

- Indexed from `/Applications`, `/System/Applications`, `~/Applications` (+ subfolders like `Utilities`).
- Running apps show a small indicator.

| Key | Action |
|---|---|
| `Enter` | Launch / bring to front |
| `⌘K` → Quit | Quit app (running only) |
| `⌘K` → Force Quit | Force quit (running only) |
| `⌘K` → Reveal in Finder | |

### 4.2 Files

- Indexed from a **configured list of folders** only (e.g. `~/Desktop`, `~/Documents`, `~/dev`).
- Skips noise: `.git`, `node_modules`, `.build`, caches, hidden files (configurable ignore patterns).
- Kept fresh via FSEvents; index lives in memory.

| Key | Action |
|---|---|
| `Enter` | Open with default app |
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
- **No filtering for now** — this includes copies from password managers. *(Revisit: concealed-type skip, ignore-app list, pause hotkey.)*
- Stored locally in SQLite; images stored as files with thumbnails.
- Screenshots: set macOS to save screenshots to the clipboard (`⌘⇧5` → Options → Save to → Clipboard, or use `⌘⌃⇧4`). They then land in history automatically. **No code needed.**

### 5.2 Retention

Both limits apply; whichever triggers first wins:

- **Size cap** in GB (e.g. 2 GB) — oldest dropped first.
- **Max age** in days (e.g. 30) — older items deleted.
- **Pinned items are never dropped.**

### 5.3 Browsing

- Opened via `⌘⇧V` or the `c ` prefix.
- List with preview pane (text, image, file info, URL).
- Pinned items on top, then newest first.
- **Search** over text content and file names.

### 5.4 Actions

| Key | Action |
|---|---|
| `Enter` | **Paste into previous app** (window closes, item pasted at cursor; needs Accessibility permission) |
| `⌘K` → Copy to clipboard | Moves item to the top of history and onto the clipboard, so a normal `⌘V` pastes it |
| `⌘K` → Paste as plain text | Strip formatting |
| `⌘K` → Pin / Unpin | |
| `⌘K` → Delete | |
| `⌘K` → Edit text | In-panel editor; saving creates a new entry at the top and puts it on the clipboard (original kept) |
| `⌘K` → Edit image | Opens in Preview; when saved, the edited image comes back as a new entry at the top |
| `⌘K` → Save as file | Images / text to a file |
| `⌘K` → Open URL | For copied links |
| `⌘K` → Reveal in Finder | For copied files |

---

## 6. Calculator

Typed directly in the launcher; result shows as the top row. `Enter` **copies the result** and closes.

- **Math:** `+ - * / ^ %`, parentheses, `sqrt`, `sin`/`cos`/`tan`, `log`/`ln`, `pi`, `e`.
- **Units:** length, mass, volume, temperature, data size, time, speed — e.g. `5 km in mi`, `200 MB in GB`, `30 c in f`.
- **Currency:** e.g. `100 usd in eur`. Rates fetched once a day from a free source (e.g. ECB via frankfurter.app), cached on disk, last rates used offline. **This is the app's only network access.**
- **Programmer:** hex / binary / octal / decimal, bit ops — e.g. `0xff in bin`, `1 << 8`, `0b1010 & 0b0110`.

---

## 7. App commands (in the launcher)

Since there is no menu bar icon, these are searchable commands:

- **Open config** — opens `config.toml` in the default editor
- **Reload config** (also automatic on save)
- **Pause / resume clipboard recording**
- **Clear clipboard history** (keeps pinned)
- **Quit launcher**

---

## 8. Configuration

Single file, no settings window: `~/.config/launcher/config.toml`. Reloaded automatically on save.

```toml
[hotkeys]
launcher  = "cmd+p"
clipboard = "cmd+shift+v"

[launcher]
folders = ["~/Desktop", "~/Documents", "~/Downloads", "~/dev"]
ignore  = [".git", "node_modules", ".build", "*.photoslibrary"]
max_depth = 6

[actions]
terminal = "Ghostty"   # Terminal | iTerm | Ghostty | Warp | …

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
- Global hotkeys: `KeyboardShortcuts` (sindresorhus) or Carbon `RegisterEventHotKey`.
- Storage: SQLite (GRDB). Config: TOML (TOMLKit).
- Paste: `CGEvent` ⌘V into the previously active app → requires **Accessibility** permission.
- Icons loaded lazily, cached in `NSCache`.
- Always build/profile in Release.

---

## 11. Open questions

- [ ] **Pick a cool final name** (replace the `launcher` codename everywhere)
- [ ] Clipboard hotkey (default `⌘⇧V`)
- [ ] Clipboard privacy: skip password managers? ignore-app list? pause hotkey?
- [ ] Default size cap / max age values
