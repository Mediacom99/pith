# Milestone 1: launcher

Goal: ⌘P opens a launcher that finds and opens apps, then files and folders, in one frame and without lag
(`FEATURES.md` §1–4, §7, §8). Clipboard and calculator come in later milestones.

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Scaffold: panel, hotkey, app index, fuzzy search

Status: **in review**. Built, 21 unit tests and lint pass, `make bench` measured. It hasn't been run on screen yet:
Edoardo's first `make run` checks the glass look, focus, and that apps come to the front when opened from a
non-active app.

- Swift Package with `LauncherCore` (logic) and `Launcher` (AppKit). `make app` builds an ad-hoc signed `.app` with
  `LSUIElement`.
- A pre-built, non-activating, borderless `NSPanel` with Liquid Glass, centered on the screen under the mouse. It's a
  search bar that grows when there are results.
- ⌘P registered through Carbon toggles the panel. It hides on ⎋, on losing focus, and after opening an app.
- In-memory app index of `/Applications`, `/System/Applications` and `~/Applications`, up to 3 folders deep. It
  matches on localized names and file names, and FSEvents triggers a rescan.
- fzf-style fuzzy search. ↑/↓ and ⌃K/⌃J move, ⏎ (or a double click) opens.
- Not yet: Finder isn't indexed (it lives in `/System/Library/CoreServices`).

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
