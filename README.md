# Pith

**A keyboard-only launcher for macOS that opens in one keystroke and stays out of the way.**

Press ⌘P from any app, type a few letters, press ⏎. Apps, files and folders in one ranked list, with the actions you
need on ⌘K. Native AppKit, always resident, no account, no telemetry.

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000?logo=apple&logoColor=white)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-only-000)
![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)
![Dependencies: 1](https://img.shields.io/badge/dependencies-1%20%28Sparkle%29-2ea44f)

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/snapshots/recent-dark.png">
    <img src="docs/snapshots/recent-light.png" width="680" alt="The launcher open on its recent list: a large tile shows the selected file, Quarterly_Budget_Review.pdf, with Open ↩ and Actions ⌘K; below it a compact list of recent apps, files and folders.">
  </picture>
</p>

> Pith: the essential part, and nothing else. It's in active development, and I use it every day.

## Why

I used Raycast, and I think they did a great job. But all I ever needed was the launcher. I don't need most of the
tools, I'm tired of AI being put into everything, and RAM isn't something I can hand out freely to my programs
anymore.

So this is a launcher for people who need a launcher. Not a whole app environment hidden behind one, built mostly to
justify a subscription.

- **Instant.** Built at launch, indexes in memory: ⌘P only shows what's ready.
- **Keyboard only.** The row you want is usually the first.
- **Small.** Native AppKit and Swift, one dependency (Sparkle, for updates), ~0 % CPU when idle.
- **Private.** No account, no telemetry, no AI. The network is only for a daily update check, and currency rates for
  the planned calculator.
- **Native.** It follows the system's appearance and is configured with a text file.

## Features

<table>
  <tr>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/snapshots/search-dark.png">
        <img src="docs/snapshots/search-light.png" alt="Typing “te”: TextEdit on the tile with Open ↩ and Actions ⌘K, then Image Capture, Stickies and Quit Pith.">
      </picture>
      <p align="center"><sub><b>Type a few letters, press ⏎</b></sub></p>
    </td>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/snapshots/actions-dark.png">
        <img src="docs/snapshots/actions-light.png" alt="⌘K on a file: the file stays on the tile, the list shows its actions.">
      </picture>
      <p align="center"><sub><b>⌘K</b>: actions for what’s selected</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/snapshots/force-quit-dark.png">
        <img src="docs/snapshots/force-quit-light.png" alt="Finder’s actions with Force Quit waiting for a second Return, in red.">
      </picture>
      <p align="center"><sub><b>Force Quit</b> asks for a second ⏎</sub></p>
    </td>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/snapshots/problem-dark.png">
        <img src="docs/snapshots/problem-light.png" alt="A config problem at the top of the list, with Open Config ↩ on the tile.">
      </picture>
      <p align="center"><sub><b>Config mistakes</b> show up; ⏎ opens the file</sub></p>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/snapshots/long-names-dark.png">
        <img src="docs/snapshots/long-names-light.png" alt="Long file and folder names, each cut in the middle so the start and the extension stay visible.">
      </picture>
      <p align="center"><sub><b>Long names</b> are cut in the middle</sub></p>
    </td>
    <td width="50%" valign="top">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/snapshots/bar-dark.png">
        <img src="docs/snapshots/bar-light.png" alt="The launcher as just its search bar, with nothing listed.">
      </picture>
      <p align="center"><sub>Or <b>just the search bar</b> until you type</sub></p>
    </td>
  </tr>
</table>

**Also:** Quick Look (Space or ⌘Y) · Zip in the background, with a notification · files indexed in memory and kept
live with FSEvents · empty state of your choice (recent, running apps, or nothing) · starts at login · no Dock or menu
bar icon.

### Keys

| Key | What it does |
|---|---|
| ⌘P | Open or close the launcher, from any app |
| ⌘⇧V, or Clipboard History in the launcher (type `c`) | Open the clipboard history; ⌫ on its empty field goes back to the launcher |
| ↑ ↓ or ⌃K ⌃J | Move the selection |
| ⏎ | Open the selected item, run the selected action, or paste the selected clip into the app you were in |
| ⌘K | Show the selected item's actions, or go back to the search |
| ⌘Q ⌘W ⌘E ⌘R ⌘T ⌘Y ⌘U | In ⌘K, run the 1st to 7th action (each row shows its letter) |
| ⎋ | Back one level, or close |
| ⌘Y, or Space with an empty field | Quick Look the selected file |

These are the defaults: every one of them can be changed in the config, under `[hotkeys]` and `[keys]`.

## Install

In Terminal (macOS 26 Tahoe or later, Apple Silicon):

```sh
curl -fsSL https://pith.edoardobertoli.xyz/install.sh | sh
```

It downloads Pith, checks that it's signed with Pith's certificate, puts it in Applications and opens it. A file curl
downloads isn't marked as coming from the internet, so macOS doesn't stop Pith the first time (decision 57).

Or download [Pith.dmg](https://pith.edoardobertoli.xyz/Pith.dmg) and open it. In
the window that opens, drag Pith onto Applications. Pith isn't notarized, so macOS stops it the first time you open it:
press Done, then in System Settings, Privacy & Security, press Open Anyway and confirm. Then press ⌘P. The first paste
from the clipboard history asks for Accessibility, which pasting needs. Pith starts at login and updates itself from
then on.

### From source

Requirements: the same Mac, and Xcode with Swift 6.4.

```sh
git clone https://github.com/Mediacom99/pith.git
cd pith
make install    # builds, copies to /Applications and launches
```

Then press ⌘P. The launcher takes ⌘P from every app, including Print; you can change the hotkey in the config.
`make uninstall` quits it and removes it.

The clipboard pastes into the app you were in, which needs Accessibility access (System Settings, Privacy & Security).
Run `make certificate` once before `make install`: it creates a local signing certificate (macOS asks for your
password), so the access you give survives reinstalls.

### Releases

Pith updates itself with [Sparkle](https://sparkle-project.org) from `pith.edoardobertoli.xyz`.
- **Once:**
  - `make update-key` creates the key that signs updates, in your keychain, and puts its public half in
    `Support/Info.plist`. Commit that.
  - `npx wrangler login` connects to the Cloudflare account that has the domain.
- **Each release:**
  1. Raise the version in `Support/Info.plist`: 0.\<milestone\>.\<patch\>.
  2. Commit.
  3. Run `make publish`. It builds and signs the app, zips it for the feed, makes the installer, tags the commit
     `v<version>`, and puts the zip, the installer and the signed update feed online.
- **What people get:**
  - A first install comes from `https://pith.edoardobertoli.xyz/Pith.dmg`, the installer: a window to drag Pith into
    Applications from, which says how to get past the first open.
  - After that, Pith checks at most once a day and downloads an update in the background. Update Pith in the
    launcher restarts into it; otherwise it installs when Pith quits.
  - Check for Updates in the launcher checks right away, without waiting for the day.
  - A notification says when it has updated, or why it couldn't.
  - Settings, history and Accessibility access carry over.
  - The Quit Pith tile shows the version, so a report can say which build it's about.

Pith isn't notarized, so the first install is blocked once, and they press Open Anyway in System Settings, Privacy &
Security. Their Mac needs macOS 26 and Apple Silicon. `make package` alone makes the zip and the installer without
publishing them.

The site's front page is `site/index.html`, the landing page to send people to. `make publish` deploys it with each
release; to change only the page, `make page` assembles it in `.build/site` to look at, and `make site` deploys it.

## Configuration

Settings live in `~/.config/pith/config.toml`. It's created with commented defaults on first launch, and saved
changes apply right away. A mistake shows up as a row at the top of the launcher, and ⏎ on it opens the file; until
it's fixed, the settings it touches stay as they were.

```toml
[hotkeys]
launcher = "cmd+p"
clipboard = "cmd+shift+v"   # "" turns it off

[keys]                      # the keys inside Pith: one, or a list; [] turns one off
up = ["up", "ctrl+k"]
down = ["down", "ctrl+j"]
open = "return"
actions = "cmd+k"
back = "escape"
preview = ["cmd+y", "space"]
run_actions = ["cmd+q", "cmd+w", "cmd+e", "cmd+r", "cmd+t", "cmd+y", "cmd+u"]
to_launcher = "backspace"   # from the clipboard back to the launcher

[launcher]
empty_state = "recent"      # "recent", "running" or "none"
clipboard_alias = "c"       # "c" lists Clipboard History first; "c " opens the clipboard
launch_at_login = true
folders = ["~"]             # a folder here is searched even inside one ignore skips: "~/Dropbox", "~/.config"
ignore = [".*", "~/Library", "node_modules", ".build", "*.photoslibrary"]
max_depth = 6

[clipboard]
max_size_gb = 2             # whichever is reached first drops the oldest items; pinned ones stay
max_age_days = 30

[actions]
terminal = "Ghostty"        # used by "Open in Terminal"

[open_with]
md  = "Visual Studio Code"  # extension or type → app
pdf = "Preview"

[open_links]
https = "Firefox"           # URL scheme → app, for links from the clipboard (https covers http)
```

## Performance

The targets are requirements, and every change is measured against them, not assumed.

| | Target | Measured now |
|---|---|---|
| ⌘P → panel on screen | one frame | 0.4 ms of the app's own work; 23 ms on screen, mostly the window server (being worked on) |
| Keystroke → results | under 5 ms | ~2 ms of work over 111 apps and 35,000+ files; 7–12 ms on screen (being worked on) |
| Idle CPU | ~0 % | ~0 %: no timers or polling, only events |
| Memory | under 50 MB | 39 MB |

How it gets there:
- Nothing blocks the main thread. File I/O, icon rendering and app launches run on background workers.
- Icons are rendered once, at their exact pixel size.
- Rows use fixed frames, and the panel's rounded background is drawn by the compositor, not the CPU.

`make bench` measures the algorithms, `make logs` the live latencies, and `make stats` memory and CPU.

## Roadmap

- [x] Launcher: apps, files, folders, ⌘K actions, Quick Look, Zip
- [x] Stage, the visual design: the tile, compact rows, light and dark
- [x] Updates: Pith updates itself from `pith.edoardobertoli.xyz`, with Check for Updates in the launcher
- [ ] Clipboard manager (⌘⇧V, in progress): history with previews, pinned items, search, paste into the previous app
- [ ] The clipboard's text editor and Edit Image (after the clipboard, decisions 36 and 40)
- [ ] Calculator: math, units, currency and programmer expressions, inline as the top result
- [ ] On-screen latency down to the targets

## Development

```sh
make            # list every target
make run        # build and launch a dev copy (it takes ⌘P)
make test       # unit and AppKit tests (Swift Testing)
make lint       # swift-format, strict
make bench      # benchmarks, in a release build
make snapshots  # draw the panel's states, light and dark, into docs/snapshots/
```

The code is a Swift package with no Xcode project:
- `Sources/LauncherCore`: the pure logic: scanning, the in-memory index, fuzzy matching, ranking, FSEvents. It never
  imports AppKit.
- `Sources/Launcher`: the AppKit app.

More in the docs:
- [`FEATURES.md`](FEATURES.md): the spec.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md): the decision log, threads, icons and measurements.
- [`docs/DESIGN.md`](docs/DESIGN.md): the design system's short map, with the full text in
  [`docs/.impeccable/design-full.md`](docs/.impeccable/design-full.md).
- [`docs/PRODUCT.md`](docs/PRODUCT.md): who it's for.
- [`docs/BRIEF-CLIPBOARD.md`](docs/BRIEF-CLIPBOARD.md): the clipboard's design brief.
