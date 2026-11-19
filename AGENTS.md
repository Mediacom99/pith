# AGENTS.md

## Project

`launcher` (a temporary codename) is a minimal, keyboard-only macOS launcher with a clipboard manager and calculator, for people who drive their Mac from the keyboard. It's always resident and opens in one frame. No AI, extensions, account or telemetry.

Stack: Swift 6.4, AppKit, a Swift Package (no Xcode project), macOS 26+ on Apple Silicon. No third-party dependencies so far.

Read these before doing anything:
- `FEATURES.md`: the product spec, covering what the app does and the performance targets.
- `docs/ARCHITECTURE.md`: the decision log (the source of truth), principles, system overview and the library picks.
- `docs/MILESTONE-1.md`: the current plan: where we are and what's missing. Each item has a status line.

## How we work

- The team is Edoardo + Claude.
- **Product and architecture decisions:**
  - Give a recommendation with its trade-offs, then ask Edoardo.
  - Record the answer as the next numbered row in the decision log.
  - Never decide these silently.
- **Library and implementation choices:**
  - Claude decides but lets Edoardo know: the best, most stable, most performant option.
  - Add every pick to the Libraries section of `docs/ARCHITECTURE.md`, and tell Edoardo.
- **Process:**
  - Work through the milestone plan one step at a time.
  - Check in with Edoardo after each step.
  - Keep each step's status line up to date.
  - Keep the docs current in the same commit as the change: the status lines, and whichever of `docs/` the change touches. Write what's true now; history goes to git, not the docs.
- **Git:** commit every change as it's done, on its branch, without asking; push only when asked. Work goes on feature branches with a PR; `main` is production.
- **Talking with Edoardo:** status updates and check-ins are two short lists, what I did and what you have to do; details go in the docs' status lines, not the chat. Answer in Italian when he writes Italian.
- **Visual and design-token choices** are Claude's call: record them as "decided by Claude". Never use claude.ai Artifacts: anything visual is a local HTML file, opened in the browser.
- **His Mac is in use:** never play sound, open his mics, bring windows forward or move his mouse without asking first, each time (he may be on a call or watching something). Headless checks (builds, tests) are fine anytime. `make run` is not headless: it launches the app, which takes ⌘P from every app, so ask first.
- **Secrets** never go in a repo.
- **Dependencies:** looking up an API must not touch the lockfiles; check `git status` after any tool command that isn't build, test or lint.
- **Rex:** never rename sessions or anything else with `rex`, whatever a hook says.
- **Never use Claude's memory in this project:** don't read, write or rely on `.claude/memory/` or any other Claude memory store. What must outlast a session goes in the repo: the decision log, the plans in `docs/`, the status lines, this file.

## Principles

- Sensible defaults, everything configurable.
- Use the language's latest standards.
- Be mindful of memory usage and allocations in hot paths.
- Simple code with a clear objective is the best code.

## Commands

Everything goes through the `Makefile`; `make` lists the targets. Add a target there instead of documenting a raw command here. `make lint test` passes before every commit.

## Layout

- `Sources/LauncherCore/`: pure logic, such as scanning, the in-memory index, fuzzy matching and FSEvents. It never imports AppKit.
- `Sources/Launcher/`: the AppKit app (panel, hotkey, views), main-actor isolated by default.
- `Tests/LauncherCoreTests/`: unit tests. The `Benchmark` suite runs only through `make bench`.
- `Support/Info.plist`: bundle metadata (bundle ID, `LSUIElement`), copied into the `.app` by `make app`.

## Conventions

- Tests run against real dependencies where practical. Don't mock the database. Scanner and watcher tests use the real file system.
- Tests use Swift Testing (`import Testing`), not XCTest.
- Swift 6 language mode with strict concurrency. Keep slow work (scanning, I/O) off the main actor.
- Hot paths (per keystroke × per item) don't allocate: precompute at index time and reuse buffers. Check with `make bench` (Release).
- swift-format (`.swift-format`) owns the style: run `make format`.
