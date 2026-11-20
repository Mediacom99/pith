# Design plan

Goal: a deliberate look for every surface in `FEATURES.md`, done through the impeccable skill (decisions 24–27).

- **Surfaces already built:** the search bar; the app, file, folder and command rows; the empty states; the ⌘K
  actions and Open with…; config problems. These get the new design.
- **Surfaces still to build:** the calculator row (§6); the clipboard browser with its preview pane, pinned items and
  in-panel text editor (§5). These get a design brief that their milestones build from.
- **What doesn't change:** the speed targets (one frame from ⌘P, under 5 ms per keystroke), and an opaque panel with
  no animation and no blur.

This plan runs alongside the milestone plans.

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Snapshots

Status: **done**.
- `make snapshots` draws the panel, off screen, into `docs/snapshots/`: the search bar, recent, search, ⌘K actions
  and a config problem, each in light and dark.
- The files come out identical on every run, so git shows only real changes.

## 2. Product context

Status: **done**.
- `/impeccable init` wrote `docs/PRODUCT.md`: the users, purpose, positioning and constraints.
- Its platform is `ios`, and a macOS section overrides the iPhone rules: keyboard, one panel, fixed type sizes, no
  materials or motion, and snapshots for screenshots.
- The audience is Edoardo first and others later, with WCAG AA contrast plus the keyboard as the accessibility bar
  (decision 27).

## 3. Critique and audit

Status: **in progress** (the critique is done and its three bugs are fixed; the audit is next).
- `/impeccable critique` and `/impeccable audit`, run on the snapshots and the code.
- Critique: 25/40 (Acceptable). It's saved in `.impeccable/critique/`, which isn't committed. Its five priority issues:
  - **P1:** symbols never change on the selection, and light mode draws them black instead of grey. A selected
    symbol in dark mode is 1.86:1, below the 3:1 of decision 27.
  - **P1:** the 8th row is cut off. Eight 44 pt rows end at 425 pt in a 421 pt panel, because the inset style pads
    16 pt above the first row. The bar and the list don't share a grid either: the magnifier is centered at 30 pt
    against icons at 38 pt, and the query starts at 54 pt against titles at 64 pt.
  - **P2:** Force Quit runs on one ⏎ with no confirmation, and a failed Move to Trash only goes to the log.
  - **P2:** the ⌘K context ("Actions for …") is the placeholder, so it disappears as soon as you type a filter.
  - **P2:** nothing on screen says what ⏎ does, that ⌘K exists, or that ⏎ on a problem opens the config.
- Fixed, as Edoardo chose (the other two go to step 4):
  - Symbols are rendered twice, in the secondary label color and in white for the selected row, and the running
    dot turns white too. The fill is now source-in, so light mode is grey as intended. That's 14 more symbol
    bitmaps, about 176 KB.
  - A plain table with our own selection (8 pt corners, 10 pt from the sides) and overlay scrollers. Eight rows
    now end exactly inside the 421 pt panel, and the selection keeps its width when the list scrolls.
  - The bar and the rows share one grid: icons and the magnifier on one column (centered at 36 pt), and titles and
    the query from 62 pt.
  - Force Quit waits for a second ⏎ (decision 28). ⎋, typing or moving the selection cancels it.
  - Tests: `forceQuitWaitsForASecondReturn` (with quitting swapped out, so no real app is quit) and
    `eightRowsFitAndShareTheBarsGrid`. A new snapshot state shows the confirmation: `force-quit`.
- Still open: a failed Move to Trash only goes to the log (step 7).
- Add the snapshot states the review needs, such as `running`, Open with… and long names.

## 4. Visual direction

Status: **todo**.
- Claude offers four directions as local HTML mockups, opened in the browser: Native Tahoe, rofi-dense,
  Raycast-like, and one of Claude's own. Each one shows the launcher, the calculator row and the clipboard browser.
- Each direction also answers the critique's two design findings: where the ⌘K context lives while you filter, and
  how the panel shows what ⏎ and ⌘K do.
- Edoardo picks one (decision 25). The pick goes in the decision log.
- `docs/DESIGN.md` records the resulting system: type, colors, spacing, rows, selection and symbols.

## 5. The launcher in the new design

Status: **todo**.
- Apply the chosen direction to the built surfaces, and fix what step 3 found.
- Regenerate the snapshots, and state the `make bench` UI numbers here; they stay within the targets.

## 6. Briefs for the planned surfaces

Status: **todo**.
- Run `/impeccable shape` for the calculator row, the clipboard browser (list, preview pane, pinned items) and the
  text editor.
- Their milestone plans point to the briefs.

## 7. Polish

Status: **todo**.
- `/impeccable polish` and `/impeccable clarify` cover the copy: the placeholder, problem rows and action names.
- `/impeccable harden`: a failed Move to Trash is reported, not only logged.
- Check AA contrast in light and dark, then take the final snapshots.
