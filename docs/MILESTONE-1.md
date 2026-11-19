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

Status: **todo**. The index holds apps and launcher commands: Open Config, Reload Config, Quit Launcher. Finder is
indexed, and the launcher leaves itself out.

## 3. Config file (feature 16)

Status: **todo**. `~/.config/launcher/config.toml`, created with commented defaults on first use and reloaded on save.
It sets the launcher hotkey, the empty state (`recent`, `running` or `none`) and launch at login. A config error shows
up as a row in the launcher, and ⏎ on that row opens the file.

## 4. Running apps (feature 7)

Status: **todo**. A running indicator on app rows. Apps are tracked in most-recently-used order for the `running`
empty state.

## 5. Learned ranking and the empty state (feature 6, decisions 11–13)

Status: **todo**. A history of what you open, kept on disk off the main thread, adds a frequency and recency boost to
the match score. Before you type, the launcher shows recent items, running apps, or nothing.

## 6. ⌘K actions (feature 8)

Status: **todo**. ⌘K on an app lists Open, Reveal in Finder, and Quit and Force Quit for running apps. Typing filters
the list, ⏎ runs an action, and ⎋ goes back to the results.

## 7. Icons follow the icon style (feature 10)

Status: **todo**. Icons render under the current appearance and re-render when the light/dark appearance or the
system icon style (Default, Dark, Clear, Tinted) changes.

## 8. Launch at login (feature 18, decision 14)

Status: **todo**. `SMAppService`, on by default, registered only by a copy running from an Applications folder.
`make install` puts the app in `~/Applications`.

## 9. Performance pass

Status: **todo**. Measure ⌘P → visible, keystroke → results, idle CPU, idle memory and threads against `FEATURES.md`
§1, and fix whatever is over: the 39 ms first ⌘P, and keystrokes still over 5 ms.
