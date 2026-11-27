# AGENTS.md

## Project

Pith is a minimal, keyboard-only macOS launcher with a clipboard manager and calculator, for people who drive their Mac from the keyboard. It's always resident and opens in one frame. No AI, extension store, account or telemetry; Lua scripting of the user's own is planned for later (decision 70).

Stack: Swift 6.4, AppKit, a Swift Package (no Xcode project), macOS 26+ on Apple Silicon. One third-party dependency: Sparkle, for updates (decision 48).

Read these before doing anything:
- `FEATURES.md`: the product spec, covering what the app does and the performance targets.
- `docs/ARCHITECTURE.md`: the decision log (the source of truth), principles, system overview and the library picks.
- `docs/MILESTONE-*.md`: the plans, one per milestone: where we are and what's missing. Each step has a status line.

## How we work

- The team is the maintainer + Claude.
- **Product and architecture decisions:**
  - Give a recommendation with its trade-offs, then ask the maintainer.
  - Record the answer as the next numbered row in the decision log.
  - Never decide these silently.
- **Library and implementation choices:**
  - Claude decides but lets the maintainer know: the best, most stable, most performant option.
  - Add every pick to the Libraries section of `docs/ARCHITECTURE.md`, and tell the maintainer.
- **Process:**
  - Work through the milestone plan one step at a time.
  - Check in with the maintainer after each step.
  - Keep each step's status line up to date.
  - Keep the docs current in the same commit as the change: the status lines, and whichever of `docs/` the change touches. Write what's true now; history goes to git, not the docs.
- **Git:** commit every change as it's done, on its branch, without asking. The remote is the public GitHub repo `Mediacom99/pith`. Changes flow one way, and none skips a step: a feature branch or the milestone branch (`search/milestone-4`) → a PR into `staging` → a PR from `staging` into `main`, the release branch, when the maintainer says so. Releases are published from `main` only. Up to `staging`, Claude goes on its own (decision 75): once `make lint test` passes, it pushes the branch, opens the PR into `staging` and merges it, then says so. From `staging` into `main`, Claude asks the maintainer first, every time, and merges only when they say so. A ruleset on both requires a pull request with an approving review, no force pushes and no deletions; only the repo's admin bypasses it, so PRs merge with `gh pr merge --admin`.
- **Talking with the maintainer:** status updates and check-ins are two short lists, what I did and what you have to do; details go in the docs' status lines, not the chat. Answer in Italian when the maintainer writes Italian.
- **Design:**
  - UI/UX work goes through the impeccable skill (`/impeccable …`, decision 24). It reads `docs/PRODUCT.md` (product context) and `docs/DESIGN.md` (the design system).
  - `docs/DESIGN.md` is impeccable's short map of the design system: its tokens and rules. The full text is
    `docs/.impeccable/design-full.md`. To change it, edit the full text, move it back over `docs/DESIGN.md`, and
    have impeccable rebuild the map (`impeccable design-compact --write`). Then bring `.impeccable/design.json` up
    to date (`/impeccable document`, sidecar only).
  - The plan is `docs/DESIGN-PLAN.md`, one status line per step, alongside the milestone plans (decision 26).
  - The visual direction is the maintainer's call: offer options, they pick. Exact values (sizes, colors, spacing) are Claude's: record them as "Claude" in the Visual decisions table (decision 25).
  - Impeccable can't run the app: `make snapshots` draws the panel's states, light and dark, into `docs/snapshots/` without putting anything on screen. Regenerate and commit them with every visual change.
  - Never use claude.ai Artifacts: anything visual is a local HTML file, opened in the browser.
- **The maintainer's Mac is in use:** never play sound, open its mics, bring windows forward or move the mouse without asking first, each time (they may be on a call or watching something). Headless checks (builds, tests) are fine anytime. `make run` and `make install` are not headless: they launch the app, which takes ⌘P from every app, so ask first.
- **The maintainer's daily copy:** they use Pith in place of Raycast: the copy in `/Applications`, installed with the
  Terminal line, signed with the local certificate (decision 41) so its Accessibility access survives updates, and
  updating itself (decisions 48–50). `make install` puts a branch build there to try, until the next update replaces
  it. A change reaches it, and whoever else has Pith, as a release (`docs/RELEASING.md`): the version raised in
  `Support/Info.plist` on the feature or milestone branch, merged by the maintainer into `staging` and then `main`,
  `make publish` on `main`, then Check for Updates in the launcher. Never publish from any other branch. When they stop
  using it (back to another launcher), remind them and remove it.
- **The repo is public** (decision 65) and GPL-3.0 (decision 66): everything committed, history included, is
  public. Nothing personal goes in it, as with the maintainer's work below.
- **Secrets** never go in a repo.
- **The maintainer's work stays out:** never mention their employer, clients or work projects anywhere: code, tests, docs, commit messages, or chat examples. Don't copy real file or folder names from their Mac into the repo either; tests and docs use made-up examples (`Acme`, `Quarterly_Budget_Review.pdf`).
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

Traps:
- Pith's log: `/usr/bin/log show --predicate 'subsystem == "dev.edoardo.pith"' --info` (zsh's `log` is a builtin), outside the sandbox.
- A new subdomain can stay unresolvable on the maintainer's Mac from a cached failed lookup: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`, which they run themselves (it needs their password).
- `make site` replaces everything the Worker serves, so it needs the feed and builds a `make publish` from this checkout left in `.build/site`.
- DESIGN.md: *move* the edited full text over `docs/DESIGN.md` before `impeccable design-compact --write`; it refuses while `docs/.impeccable/design-full.md` exists.
- Page captures: `impeccable shot` for phone widths (headless Chrome won't go below about 500 px); `impeccable motion-capture` takes waits up to 2000 ms, arrow keys but not Page Down or Home, and no playback over 10 s.
- A scrolled page can't be captured: `impeccable shot` resets the scroll, and headless Chrome draws a blank frame after a scripted scroll. Measure instead: inject a script that scrolls, writes `getBoundingClientRect()` values into a `data-` attribute, and read it with Chrome's `--headless=new --dump-dom`.
- Notifications that reach Notification Center but show no banner, for every app: the screen is being shared or
  mirrored (or a Focus is on). `donotdisturbd` logs `isScreenShared=1` and `interruptionSuppression: silence` in
  `/usr/bin/log show --predicate 'process == "NotificationCenter" OR subsystem == "com.apple.donotdisturb"'`.
- A banner with a blank icon while the app has one is macOS's icon cache, kept from before the icon existed (step
  11): `sudo rm -rf /Library/Caches/com.apple.iconservices.store; sudo killall iconservicesd; killall
  iconservicesagent NotificationCenter usernoted`, which the maintainer runs themselves (it needs their password). No restart.
- macOS's notification system (`usernoted`) keeps an app's record, by bundle id, until no copy of the app is left, then drops it when it restarts. `tccutil reset All dev.edoardo.pith` works only while LaunchServices still knows a copy. `sfltool dumpbtm` hangs waiting for a password. `make app` copies get registered with LaunchServices too (`lsregister -u .build/Pith.app` drops one).

## Layout

- `Sources/LauncherCore/`: pure logic, such as scanning, the in-memory index, fuzzy matching and FSEvents. It never imports AppKit.
- `Sources/Launcher/`: the AppKit app (panel, hotkey, views), main-actor isolated by default.
- `Tests/LauncherCoreTests/`: unit tests for the core.
- `Tests/LauncherTests/`: AppKit layout tests, the UI benchmark and the panel snapshots, in real panels that are never put on screen.
- Suites named `…Benchmark` run only through `make bench`, and `…Snapshots` only through `make snapshots`.
- `docs/snapshots/`: the panel's states as PNGs, written by `make snapshots`.
- `Support/Info.plist`: bundle metadata (bundle ID, `LSUIElement`, Sparkle's feed and key), copied into the `.app` by
  `make app`.
- `Support/AppIcon.svg`: the app icon's source; `make icon` redraws the committed `Support/AppIcon.icns` and
  `Support/Assets.car` (the same icon as an asset catalog) from it.
- `Support/wrangler.toml`: `pith.edoardobertoli.xyz` on Cloudflare, where `make publish` puts the update feed and the
  builds.
- `site/`: the landing page on `pith.edoardobertoli.xyz` (decision 51). `make page` assembles it in `.build/site` with
  its snapshots, `make site` deploys it with the published feed; it's design work, so it goes through impeccable.

## Conventions

- Tests run against real dependencies where practical. Don't mock the database. Scanner and watcher tests use the real file system.
- Tests use Swift Testing (`import Testing`), not XCTest.
- Tests never touch the real `~/.config/pith/` or `~/Library/Application Support/pith/`: use temporary files (`HistoryStore(file:)`, `TemporaryDirectory`).
- Swift 6 language mode with strict concurrency; the app target is main-actor by default. Threading follows the Performance rules above.
- swift-format (`.swift-format`) owns the style: run `make format`.
