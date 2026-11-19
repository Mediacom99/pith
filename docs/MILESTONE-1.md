# Milestone 1: launcher

Goal: ⌘P opens a launcher that finds and opens apps and launcher commands, learns from what you open, shows something
useful before you type, and is configured from one file. All of it meets the `FEATURES.md` §1 targets. Scope is
decision 10. Files and folders, the clipboard and the calculator come in later milestones.

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Scaffold: panel, hotkey, app index, fuzzy search

Status: **done**. ⌘P toggles a pre-built, non-activating, opaque panel on the screen under the mouse. Fuzzy search
covers `/Applications`, `/System/Applications` and `~/Applications`, with icons pre-rendered off the main thread. The
panel is only the search bar when there's nothing to list. Measured on screen: 24 MB idle, 0% CPU, 6 threads. The
latency work continues in step 9.

## 2. Launcher commands and Finder (features 9, 17)

Status: **in review**. Search finds the commands Open Config, Reload Config and Quit Launcher, shown with SF Symbol
icons. Finder is indexed from `/System/Library/CoreServices`, and the launcher leaves itself out of the index. Covered
by tests (commands searchable, Finder found, ids resolved). Waiting for Edoardo's run.

## 3. Config file (feature 16)

Status: **in review**.
- `~/.config/launcher/config.toml` is created with commented defaults on first launch and reloaded on save (FSEvents
  on its folder, parsed on a worker).
- It covers `[hotkeys] launcher`, `[launcher] empty_state` and `launch_at_login`.
- A wrong or unknown setting keeps its default and shows as "Config problem, line N: …" at the top of the empty state;
  ⏎ opens the file.
- A changed hotkey is swapped in at runtime. If the new one is taken, the old one stays, with a problem row.
- Config, TOML and hotkey parsing are covered by tests, including every error message.

Waiting for Edoardo's run.

## 4. Running apps (feature 7)

Status: **in review**. Running apps show a Dock-style dot under their icon, kept current from NSWorkspace launch,
activation and quit notifications. Their ids match the index (tested against the real running apps). Waiting for
Edoardo's run.

## 5. Learned ranking and the empty state (feature 6, decisions 11–13)

Status: **in review**.
- Every open is saved to `~/Library/Application Support/launcher/history.json`, atomically, on a serial worker.
  Quitting waits for pending saves.
- The history's frecency boosts the match score by up to +48.
- Before you type, the launcher shows `recent` (up to 8 items, newest first; the default), `running` (most recently
  used first, starting on the previous app) or `none`.

Covered by history and panel tests. Waiting for Edoardo's run.

## 6. ⌘K actions (feature 8)

Status: **in review**. ⌘K on an app lists Open and Reveal in Finder, plus Quit and Force Quit when it's running.
Typing filters the actions, ⏎ runs one, and ⎋ or ⌘K returns to the search and the selection you had. Reveal runs on a
worker. Covered by tests. Waiting for Edoardo's run.

## 7. Icons follow the icon style (feature 10)

Status: **in review**. Icons and symbols render under the app's appearance. All of them re-render on a light/dark
switch and on AppKit's private icon-style notification. Under the Default style, light and dark renders are identical
(measured). Untested on screen: switching to Dark, Clear or Tinted in System Settings › Appearance should update the
launcher's icons within a moment.

## 8. Launch at login (feature 18, decision 14)

Status: **in review**. `SMAppService.mainApp` registers or unregisters on a worker when `launch_at_login` changes,
and only for a copy in `/Applications` or `~/Applications`. `make install` copies the app to `~/Applications` and
launches it; `make stop` stops either copy. Not run yet: the first `make install` registers the login item, and macOS
shows its "login item added" notification.

## 9. Performance pass

Status: **in progress**. Each latency is now logged in three phases: delivery (key press → our code), update and
draw. In-process work per keystroke is ~1.6 ms (UIBenchmark) and searches take microseconds. Next: an on-screen run
with `make logs` and `make stats` to measure ⌘P → drawn (39 ms on the first ⌘P last time) and keystroke → drawn
against the 5 ms target, now that text services are off. Then fix whatever phase is over.
