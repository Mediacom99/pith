# Design plan

Goal: a deliberate look for every surface in `FEATURES.md`, done through the impeccable skill (decisions 24–27).

- **Built, in the design:** the search bar and the tile; the app, file, folder and command rows; the empty states; the
  ⌘K actions and Open With…; config problems; the clipboard (§5), from its brief.
- **Still to build:** the calculator row (§6) and the clipboard's text editor (§5, decision 36). Each gets a design
  brief that its milestone builds from.
- **What doesn't change:** the speed targets (one frame from ⌘P, under 5 ms per keystroke), and an opaque panel with
  no animation and no blur.

This plan runs alongside the milestone plans. Step 7 comes before step 6, and step 6 starts with the clipboard,
milestone 3 (decision 31).

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Snapshots

Status: **done**.
- `make snapshots` draws the panel, off screen, into `docs/snapshots/`: each launcher and clipboard state, in light and
  dark.
- The files come out the same on every run, apart from faint icon-pixel noise from the system's icon cache, so git
  shows only real changes.

## 2. Product context

Status: **done**.
- `/impeccable init` wrote `docs/PRODUCT.md`: the users, purpose, positioning and constraints.
- Its platform is `ios`, and a macOS section overrides the iPhone rules: keyboard, one panel, fixed type sizes, no
  materials or motion, and snapshots for screenshots.
- The audience is Edoardo first and others later, with WCAG AA contrast plus the keyboard as the accessibility bar
  (decision 27).

## 3. Critique and audit

Status: **done**. `/impeccable critique` (25/40) and `/impeccable audit` (15/20, then 16/20 after the fix below), on the
snapshots and the code, against decision 27's bar; the reports are in `.impeccable/`, not committed.
- Fixed here: Force Quit waits for a second ⏎ (decision 28), and rows no longer fade in when a list on screen grows
  (`rowsAddedToAListOnScreenShowAtOnce`).
- The rest (the dark selection's contrast, the ⌘K context, what ⏎ and ⌘K do, the corners and dark-mode edge) went to
  steps 4 and 5, which closed them; a failed Move to Trash went to step 7.
- Outside the bar: VoiceOver hears nothing as the selection moves, and the symbols ignore Increase Contrast.

## 4. Visual direction

Status: **done**: Edoardo picked Stage (decision 29), from four directions Claude drew as local HTML mockups (Native
Tahoe, rofi-dense, Raycast-like, Stage).
- Stage: a tile under the search bar shows what ⏎ will act on (the item, the calculator's answer, the clipboard
  preview) with the keys for ⏎ and ⌘K, over a compact list. The selected row has a quiet fill and ends in ↩. Color
  only for meaning: red for Force Quit, orange for a config problem.
- The direction contract is in `.impeccable/surfaces/` (committed), for impeccable's later passes.

## 5. The launcher in the new design

Status: **done**. Stage is built, reviewed, documented and installed: the values are in `docs/ARCHITECTURE.md`'s
Visual decisions, and the system in `docs/DESIGN.md`.
- Contrast, measured on the snapshots: quiet text 4.75:1 at worst (the folder on the dark selection), ↩ 9.4:1 light
  and 8.4:1 dark, Force Quit's red 4.7:1 and 4.9:1, the problem's orange 4.9:1.
- The panel's and the tile's rounded backgrounds are layer properties: drawn on the CPU they cost 1.4 ms per keystroke.
- The tile's 96 px icons take 5.9 MB, one per app. Edoardo kept them rendered ahead of time: rendering on demand would
  save ~5 MB but could show a result's big icon a frame late.

## 6. Briefs for the planned surfaces

Status: **done** for the clipboard, **todo** for the calculator.
- Clipboard: `docs/BRIEF-CLIPBOARD.md`, confirmed by Edoardo; `docs/MILESTONE-3.md` builds it. Shaped with him: what he copies (text, links, images,
  files), that he mostly wants the last few copies, and decisions 33–36 (newest first, ⌘⇧V, concealed copies
  skipped, the editor after milestone 3).
- Calculator: run `/impeccable shape` for its row when its milestone comes. The text editor gets its own brief after
  milestone 3 (decision 36).
- Their milestone plans point to the briefs.

## 7. Polish

Status: **done**. Polish, clarify and harden passes, checked by Edoardo in the installed app.
- **Harden:** an action that fails after the panel closes posts a notification saying what failed and why, and a
  click reveals the item (decision 32).
- **Copy:** Escape's key cap reads "esc"; commands say "Pith command" on the tile; problems say what Pith does
  meanwhile ("so the settings stay as they were", "so it's still "cmd+p"").
- **Contrast:** the key caps' glyphs use the Key color shared with the row's ↩ (8.8:1 light, 7.4:1 dark on a cap).

## 8. The landing page

Status: **in review**. `site/index.html` on `pith.edoardobertoli.xyz` (decision 51): Raycast's structure, pinned by
Edoardo, in Stage's world carried to the web; through impeccable's finish review, and documented in `DESIGN.md`'s
Website section. The direction contract is in `.impeccable/surfaces/site-index-html.md`.
- **First viewport:** the claim "Fast, small, and out of your way.", the Terminal line with its Copy (decision 67;
  Pith.dmg is a quiet line under it), and four key caps (⌘P, te, ⌘K, ⌘⇧V) that switch the real panel underneath in one
  frame, as do the same keys pressed on the page.
- **Below:** a keyboard of key caps where Pith's keys are lit and explain themselves; four reasons with measured
  numbers, the machine and the method under them; rows for the launcher, ⌘K and the clipboard; the whole
  `config.toml` beside every setting, its default and what it does, each lighting the other (the file stays pinned
  and scrolls inside itself); Edoardo's why; setting it up (the Terminal line, then the installer's four steps), how a
  setting changes and how updates arrive; and a closing ⌘P with the Terminal line.
- **Motion** (decision 53), in the keys only: presses, a one-time hero tour, chords, a retyped config value; the
  snapshots change in one frame, and Reduce Motion plays nothing by itself. Checked by impeccable's motion review.
- **Web-only additions to Stage**, in `DESIGN.md`'s Website section: a page ground (#ECECEC light, #141414 dark),
  the main action (Copy, Install) in the label color, and key caps at web sizes (7 px corners); no accent, no fades.
