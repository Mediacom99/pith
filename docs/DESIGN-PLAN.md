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

Status: **todo**.
- `/impeccable critique` and `/impeccable audit`, run on the snapshots and the code.
- Three problems the snapshots already show:
  - The 8th row is cut off.
  - When the list scrolls, the scroller narrows the selection.
  - The magnifying glass isn't aligned with the row icons.
- Add the snapshot states the review needs, such as `running`, Open with… and long names.

## 4. Visual direction

Status: **todo**.
- Claude offers two or three directions as local HTML mockups, opened in the browser. Each one shows the launcher,
  the calculator row and the clipboard browser.
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
- Check AA contrast in light and dark, then take the final snapshots.
