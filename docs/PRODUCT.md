# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## macOS (overrides the iOS rules)

The launcher is a Mac app: AppKit, macOS 26+, Apple Silicon. `ios` stands in because impeccable has no macOS platform,
and it turns on the native checks instead of the web ones (decision 24). Where the iOS guidance and this section
disagree, this section wins:

- **Input is the keyboard.** There is no touch, so the 44 pt touch-target rule doesn't apply. Hover is never an
  affordance either. The pointer is optional: a double click opens a row, and that's all it does.
- **Structure is one panel.** A floating, non-activating `NSPanel` of fixed width, on the screen under the pointer. It
  has no tab bars, navigation stacks, sheets, large titles, safe areas or edge-swipe back. Going deeper replaces the
  list in place (⌘K actions, Open with…), and ⎋ goes back one level.
- **Type has fixed point sizes.** macOS has no Dynamic Type. SF (the system font) carries the UI, and 11 pt is the floor.
- **Color comes from the semantic system colors** (`NSColor` label, secondary label, window background, separator,
  the user's accent color), so light, dark and Increase Contrast adapt on their own.
- **No materials, motion or glass.** The panel is opaque inside its rounded corners (the window is clear only so the
  corners can be round), with no blur, translucency or Liquid Glass. It appears and disappears in one frame with no
  transition. These are performance rules (`AGENTS.md`), not taste.
- **Components:** AppKit's table and text field, SF Symbols, the system notifications for Zip and failed actions,
  the system Quick Look panel.
- **Verifying:** screenshots come from `make snapshots`, never the Simulator or a browser. It draws the panel's states
  off screen, in light and dark, into `docs/snapshots/`. `make run` puts the app on Edoardo's screen, so it needs his
  OK each time. Speed is checked with `make bench` and `make logs`.

## Users

- **Now: Edoardo.** He drives his Mac from the keyboard and calls the launcher with ⌘P in the middle of other work:
  to open or switch to an app, find a file or folder, or act on one. His habits come from Raycast on the Mac (the ⌘K
  action panel) and from rofi and dmenu on Linux (instant, text-first lists).
- **Also: other keyboard-driven Mac users.** Pith is public, in beta (decisions 65, 69): a few friends use it, and
  anyone can install it with one line in Terminal or the disk image (decisions 56, 67).

## Product Purpose

One hotkey to open anything (apps, files, folders, the launcher's own commands), another to browse and paste the
clipboard history, and later a calculator, without touching the mouse. Success: it is on screen within one frame of ⌘P, the
results follow each keystroke in under 5 ms, the row you want is usually the first, and when it isn't in use it costs
nothing (~0% CPU, under 50 MB).

## Positioning

Speed and small size are the product. It's native AppKit and always resident: the panel is built at launch and the
indexes live in memory, so it opens in one frame. It has Raycast's keyboard actions with the footprint and immediacy of
rofi and dmenu. It has no AI, extension store, account or telemetry (Lua scripting, the user's own, is planned: decision 70), and touches the network only for an update
check and currency rates. Settings are a text file, not a settings window.

## Operating Context

- ⌘P works from any app. The panel never activates the launcher, so the previous app stays frontmost (paste into it
  depends on that).
- It's used glance-and-go: a few letters, a look at the top rows, ⏎. It closes on ⏎, on ⎋, or when it loses focus,
  and every close empties the field.
- Light and dark follow the system, and app icons follow the system icon style (Default, Dark, Clear, Tinted).
- Configuration is `~/.config/pith/config.toml`, reloaded on save. A bad setting shows up as a problem row at
  the top of the empty state, and ⏎ on it opens the file.

## Capabilities and Constraints

- **Built (milestones 1–3):**
  - One ranked list of apps, files and folders, with fuzzy matching word by word and a learned ranking.
  - Empty state: `recent`, `running` or `none`.
  - "running" after the name of a running app.
  - ⌘K actions for each kind of row, Open With…, Quick Look, and Zip with a notification.
  - The clipboard (§5): opened with ⌘⇧V, the `c ` prefix or Clipboard History; newest first with the tile as its
    preview, pinned clips found by typing, search, paste into the previous app, and paste next (⌃⌥V).
  - Launcher commands: Clipboard History, Pause or Resume Clipboard Recording, Clear Clipboard History, Check for
    Updates, Update Pith, Open Config, Reload Config, Quit Pith.
  - Config problems shown as rows.
  - Updates, and a notification for each (decisions 48–50).
- **Planned (`FEATURES.md`):**
  - The calculator: an inline top row for math, units, currency and programmer expressions (§6).
  - The clipboard's text editor and Edit Image (decisions 36, 40).
  - Lua scripting of the user's own, later (§12, decision 70).
  - The design covers these before they're built (decision 26).
- **Constraints:**
  - The `FEATURES.md` §1 performance targets are requirements.
  - Fixed frames, prepared ahead of time, and icons pre-rendered at their exact pixel size.
  - Nothing on the main thread blocks.
  - A visual change is measured against these targets, not assumed to be free.
- **Out of scope:** themes and a settings window (`FEATURES.md` §9). Behavior is configurable, but the look isn't
  themable.
- **Terms:** panel, search bar, tile, rows, empty state, ⌘K actions, commands, config problems, clipboard mode, clips.
- **Distribution:** a landing page at `pith.edoardobertoli.xyz` with a one-line Terminal install and a disk image,
  not notarized, that updates itself (decisions 46, 48, 51, 56, 67).
- **Undecided:** for the clipboard, an ignore-app list.

## Brand Commitments

The name is Pith (decision 30): the essential part and nothing else. The app icon is a citrus cross-section in Pith's monochrome: the white pith between the peel and the segments (decision 54). The site uses it as its favicon and beside the wordmark. The app's copy today is
short and literal ("Config problem, line 3: …", "Filter actions", "Open in Preview").

## Evidence on Hand

- `docs/snapshots/`: the panel's current states (search bar, recent, search, ⌘K actions, config problem, the
  clipboard's), in light and dark.
- `docs/ARCHITECTURE.md` (Measured): the latency, memory and idle numbers.
- There are no users besides Edoardo and a few friends yet, and no testimonials. Don't invent any. The website and the app icon exist (decisions 51, 54).

## Product Principles

1. **Speed is the feature.** Anything that costs a frame at open or a millisecond per keystroke has to earn it, and
   it's measured, not guessed.
2. **The keyboard is enough.** Every action is reachable without the mouse, and the first row should usually be the
   right one.
3. **Small scope, done excellently:** launcher, clipboard, calculator, and nothing else.
4. **Native and quiet.** It behaves like part of macOS, follows the system's appearance, accent color and icon style,
   and asks for nothing: no account, no network beyond an update check and currency rates.

## Accessibility & Inclusion

- **The bar (decision 27):**
  - WCAG AA contrast for text, meaningful symbols and the selection, in both light and dark.
  - Full keyboard operation, which the app already has.
- **Not in the bar for now:** VoiceOver, Increase Contrast and Reduce Transparency. Don't break what AppKit's
  standard controls give for free, though. With no motion, Reduce Motion doesn't apply.
- **Language:** the interface copy is in English, while app names appear in the system language (Calcolatrice for
  Calculator).
