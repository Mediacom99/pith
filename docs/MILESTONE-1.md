# Milestone 1: launcher

Goal: ⌘P opens a launcher that finds and opens apps and launcher commands, learns from what you open, shows something
useful before you type, and is configured from one file. All of it meets the `FEATURES.md` §1 targets. Scope is
decision 10. Files and folders, the clipboard and the calculator come in later milestones.

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Scaffold: panel, hotkey, app index, fuzzy search

Status: **done**. ⌘P toggles a pre-built, non-activating, opaque panel on the screen under the mouse. Fuzzy search
covers `/Applications`, `/System/Applications` and `~/Applications`, with icons pre-rendered off the main thread. The
panel is only the search bar when there's nothing to list. The latency work is step 9; today's numbers are in
`docs/ARCHITECTURE.md` (Measured).

## 2. Launcher commands and Finder (features 9, 17)

Status: **done**. Search finds the commands Open Config, Reload Config and Quit Pith, shown with SF Symbol
icons. Finder is indexed from `/System/Library/CoreServices`, and the launcher leaves itself out of the index. Covered
by tests (commands searchable, Finder found, ids resolved).

## 3. Config file (feature 16)

Status: **done**.
- `~/.config/pith/config.toml` is created with commented defaults on first launch and reloaded on save (FSEvents
  on its folder, parsed on a worker).
- It covers `[hotkeys] launcher`, `[launcher] empty_state` and `launch_at_login`.
- A wrong or unknown setting keeps its default and shows as "Config problem, line N: …" at the top of the empty state;
  ⏎ opens the file.
- A changed hotkey is swapped in at runtime. If the new one is taken, the old one stays, with a problem row.
- Config, TOML and hotkey parsing are covered by tests, including every error message.

## 4. Running apps (feature 7)

Status: **done**. Running apps show "running" after their name. The source of truth is
`NSWorkspace.runningApplications`: it's re-read on every launch or quit notification and before every show, so a
missed notification can't leave a stale indicator. Activation notifications set the order. Ids match the index
(tested against the real running apps).

## 5. Learned ranking and the empty state (feature 6, decisions 11–13)

Status: **done**.
- Every open is saved to `~/Library/Application Support/pith/history.json`, atomically, on a serial worker.
  Quitting waits for pending saves.
- The history's frecency boosts the match score by up to +48.
- Before you type, the launcher shows `recent` (up to 8 items, newest first; the default), `running` or `none`.
  `running` lists open apps most recently used first, starting on the previous app, then all other apps
  alphabetically (decision 17).
- Filling it costs ~1.7 ms in-process, even with all 114 apps.

Covered by history and panel tests.

## 6. ⌘K actions (feature 8)

Status: **done**. ⌘K on an app lists Open and Reveal in Finder, plus Quit and Force Quit when it's running.
Typing filters the actions, ⏎ runs one, and ⎋ or ⌘K returns to the search and the selection you had. Reveal runs on a
worker. Covered by tests.

## 7. Icons follow the icon style (feature 10)

Status: **done**. Icons and symbols render under the app's appearance. All of them re-render on a light/dark
switch and on AppKit's private icon-style notification. Under the Default style, light and dark renders are identical
(measured). Untested on screen: switching to Dark, Clear or Tinted in System Settings › Appearance should update the
launcher's icons within a moment.

## 8. Launch at login (feature 18, decision 14)

Status: **done**. `SMAppService.mainApp` registers or unregisters on a worker when `launch_at_login` changes,
and only for a copy in `/Applications` or `~/Applications`. `make install` copies the app to `/Applications` and
launches it; `make stop` stops either copy.

## 9. Performance pass

Status: **todo**, after milestone 3 (decision 31). Merged with milestone 2 step 8, which measures both on the same build.
