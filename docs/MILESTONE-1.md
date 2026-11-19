# Milestone 1: launcher

Goal: ⌘P opens a launcher that finds and opens apps, then files and folders, in one frame and without lag
(`FEATURES.md` §1–4, §7, §8). Clipboard and calculator come in later milestones.

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Scaffold: panel, hotkey, app index, fuzzy search

Status: **in review**. On Edoardo's first run the panel worked but icons stuttered: each one rendered on the main
thread the first time it was shown (~5 ms each, up to ~38 ms). Since then:

- icons are pre-rendered off the main thread;
- the panel is plain, opaque and fixed-size;
- rows use fixed frames;
- the table reloads only when the matches change;
- ⌘P and keystroke latencies are logged.

The 21 tests and lint pass. Still to do: the second run, with `make logs` and `make stats` to measure on screen, and
confirming that an opened app comes to the front.

- Swift Package with `LauncherCore` (logic) and `Launcher` (AppKit). `make app` builds an ad-hoc signed `.app` with
  `LSUIElement`.
- A pre-built, pre-drawn, non-activating, opaque `NSPanel`, centered on the screen under the mouse.
- ⌘P registered through Carbon toggles the panel. It hides on ⎋, on losing focus, and after opening an app.
- In-memory app index of `/Applications`, `/System/Applications` and `~/Applications`, up to 3 folders deep. It
  matches on localized names and file names, and FSEvents triggers a rescan. App icons are rendered once, in parallel,
  on workers.
- fzf-style fuzzy search. ↑/↓ and ⌃K/⌃J move, ⏎ (or a double click) opens.
- Not yet: Finder isn't indexed (it lives in `/System/Library/CoreServices`), and icons ignore the dark or tinted icon
  style.

## 2. Ranking learns from picks

Status: **todo**. Boost the match score by how often and how recently each item was opened (`FEATURES.md` §4). Needs
a small persisted store, decided at step start (it could share GRDB with the clipboard).

## 3. Running apps and the actions panel (⌘K)

Status: **todo**. Show a running indicator. ⌘K opens a sub-view with Quit, Force Quit (running apps only) and Reveal
in Finder. ⎋ goes back one level.

## 4. Files and folders index

Status: **todo**. Index the configured folders with ignore patterns and a maximum depth, kept fresh by FSEvents
(`FEATURES.md` §4.2–4.3). This needs a generic index (`AppIndex` is apps-only) and probably a search off the main
thread: 1–2 letter queries over 100k names take up to 7 ms today, above the 5 ms target. Building an index of 100k
items takes ~0.9 s.

## 5. File and folder actions

Status: **todo**. Open, Reveal in Finder, Copy path, Open with…, Quick Look (also Space and ⌘Y), Copy file, Zip
(`ditto`, in the background), Move to Trash, Open in terminal.

## 6. Config file and app commands

Status: **todo**. `~/.config/launcher/config.toml` (library picked at step start), reloaded on save. Hotkeys, folders,
ignore patterns and the terminal app become configurable. Add the launcher commands Open config, Reload config and
Quit launcher (`FEATURES.md` §7–8).

## 7. Launch at login and a performance pass

Status: **todo**. Launch at login through `SMAppService`, which needs a stable install location. Measure hotkey →
visible, keystroke → results, idle CPU and idle RAM against the `FEATURES.md` §1 targets.
