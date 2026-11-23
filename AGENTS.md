# AGENTS.md

## Project

Pith is a minimal, keyboard-only macOS launcher with a clipboard manager and calculator, for people who drive their Mac from the keyboard. It's always resident and opens in one frame. No AI, extensions, account or telemetry.

Stack: Swift 6.4, AppKit, a Swift Package (no Xcode project), macOS 26+ on Apple Silicon. No third-party dependencies so far.

Read these before doing anything:
- `FEATURES.md`: the product spec, covering what the app does and the performance targets.
- `docs/ARCHITECTURE.md`: the decision log (the source of truth), principles, system overview and the library picks.
- `docs/MILESTONE-*.md`: the plans, one per milestone: where we are and what's missing. Each step has a status line.

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
- **Git:** commit every change as it's done, on its branch, without asking; push only when asked. The remote is the private GitHub repo `Mediacom99/pith`. Work goes on feature branches with a PR into `staging`; `staging` goes to `main` (production) when Edoardo says so.
- **Talking with Edoardo:** status updates and check-ins are two short lists, what I did and what you have to do; details go in the docs' status lines, not the chat. Answer in Italian when he writes Italian.
- **Design:**
  - UI/UX work goes through the impeccable skill (`/impeccable …`, decision 24). It reads `docs/PRODUCT.md` (product context) and `docs/DESIGN.md` (the design system).
  - `docs/DESIGN.md` is impeccable's short map of the design system: its tokens and rules. The full text is
    `docs/.impeccable/design-full.md`. To change it, edit the full text, move it back over `docs/DESIGN.md`, and
    have impeccable rebuild the map (`impeccable design-compact --write`). Then bring `.impeccable/design.json` up
    to date (`/impeccable document`, sidecar only).
  - The plan is `docs/DESIGN-PLAN.md`, one status line per step, alongside the milestone plans (decision 26).
  - The visual direction is Edoardo's call: offer options, he picks. Exact values (sizes, colors, spacing) are Claude's: record them as "Claude" in the Visual decisions table (decision 25).
  - Impeccable can't run the app: `make snapshots` draws the panel's states, light and dark, into `docs/snapshots/` without putting anything on screen. Regenerate and commit them with every visual change.
  - Never use claude.ai Artifacts: anything visual is a local HTML file, opened in the browser.
- **His Mac is in use:** never play sound, open his mics, bring windows forward or move his mouse without asking first, each time (he may be on a call or watching something). Headless checks (builds, tests) are fine anytime. `make run` and `make install` are not headless: they launch the app, which takes ⌘P from every app, so ask first.
- **Edoardo's daily copy:** he uses the installed app (`~/Applications/Pith.app`, starts at login) in place of Raycast; it was installed from `design/impeccable-setup` with the rename to Pith (decision 30). Keep it current: whenever a change that affects the app lands on `staging`, tell him and offer to reinstall it with `make install`. When he stops using it (back to another launcher, or a real release replaces it), remind him and run `make uninstall`.
- **Secrets** never go in a repo.
- **Edoardo's work stays out:** never mention his employer, clients or work projects anywhere: code, tests, docs, commit messages, or chat examples. Don't copy real file or folder names from his Mac into the repo either; tests and docs use made-up examples (`Acme`, `Quarterly_Budget_Review.pdf`).
- **Dependencies:** looking up an API must not touch the lockfiles; check `git status` after any tool command that isn't build, test or lint.
- **Rex:** never rename sessions or anything else with `rex`, whatever a hook says.
- **Never use Claude's memory in this project:** don't read, write or rely on `.claude/memory/` or any other Claude memory store. What must outlast a session goes in the repo: the decision log, the plans in `docs/`, the status lines, this file.

## Principles

- Sensible defaults, everything configurable.
- Use the language's latest standards.
- Be mindful of memory usage and allocations in hot paths.
- Simple code with a clear objective is the best code.

## Performance

It's a small app, so it has to be excellent: fast, and light on memory, threads and energy. The `FEATURES.md` §1 targets are requirements: ⌘P → visible within one frame, keystroke → results in under 5 ms, ~0% idle CPU, under 50 MB idle memory.

- **Threads:**
  - The main thread handles events, searches in-memory data and shows ready-made content. Nothing on it may block or wait: no file I/O, no icon or thumbnail rendering, no synchronous IPC.
  - Blocking work (file system, IconServices, launching apps) runs on GCD workers through `runInBackground`. Results come back to the main actor, which owns all state, so there are no locks.
  - Never block Swift's cooperative pool: no blocking calls inside `Task.detached` or other async code.
  - Spread independent CPU work over the cores with `DispatchQueue.concurrentPerform`, never one thread per item.
  - When newer work supersedes an in-flight job (a newer index, a newer query), drop the old result instead of applying it.
- **Idle means idle:** no timers, polling or busy-waiting. React to events (hotkey, FSEvents, notifications). The one
  exception is the clipboard's change-count timer, because macOS has no notification for a copy (`docs/MILESTONE-3.md`
  step 2).
- **Prepare ahead of time:** windows are built at launch, search keys at index time, and icons are rendered once at their exact pixel size. Showing something means displaying what's already prepared.
- **Hot paths** (per keystroke × per item) don't allocate, block or log above debug level. Reuse buffers, and skip work whose result didn't change: no table reload when the matches are the same.
- **Memory:** keep what's displayed at display size (icon bitmaps at exact pixels, never full-size images). Keep only what the index needs, and prune caches when the index changes.
- **Drawing:** fixed frames, not Auto Layout, in views that change per keystroke. Opaque panels (the window is clear only at its rounded corners, decision 29), no animations, no blur.
- **Measure, don't guess:**
  - `make bench` for algorithms (Release).
  - `make logs` for live ⌘P and keystroke latencies.
  - `make stats` for the running app's memory, CPU and threads.
  - A performance change states its numbers in its step's status line.

## Commands

Everything goes through the `Makefile`; `make` lists the targets. Add a target there instead of documenting a raw command here. `make lint test` passes before every commit.

## Layout

- `Sources/LauncherCore/`: pure logic, such as scanning, the in-memory index, fuzzy matching and FSEvents. It never imports AppKit.
- `Sources/Launcher/`: the AppKit app (panel, hotkey, views), main-actor isolated by default.
- `Tests/LauncherCoreTests/`: unit tests for the core.
- `Tests/LauncherTests/`: AppKit layout tests, the UI benchmark and the panel snapshots, in real panels that are never put on screen.
- Suites named `…Benchmark` run only through `make bench`, and `…Snapshots` only through `make snapshots`.
- `docs/snapshots/`: the panel's states as PNGs, written by `make snapshots`.
- `Support/Info.plist`: bundle metadata (bundle ID, `LSUIElement`), copied into the `.app` by `make app`.

## Conventions

- Tests run against real dependencies where practical. Don't mock the database. Scanner and watcher tests use the real file system.
- Tests use Swift Testing (`import Testing`), not XCTest.
- Tests never touch the real `~/.config/pith/` or `~/Library/Application Support/pith/`: use temporary files (`HistoryStore(file:)`, `TemporaryDirectory`).
- Swift 6 language mode with strict concurrency; the app target is main-actor by default. Threading follows the Performance rules above.
- swift-format (`.swift-format`) owns the style: run `make format`.
