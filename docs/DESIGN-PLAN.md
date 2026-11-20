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
- `make snapshots` draws the panel, off screen, into `docs/snapshots/`: the search bar, recent, search, ⌘K actions,
  the Force Quit confirmation, a config problem, and long names in the rows and in ⌘K, each in light and dark.
- The files come out identical on every run, so git shows only real changes.

## 2. Product context

Status: **done**.
- `/impeccable init` wrote `docs/PRODUCT.md`: the users, purpose, positioning and constraints.
- Its platform is `ios`, and a macOS section overrides the iPhone rules: keyboard, one panel, fixed type sizes, no
  materials or motion, and snapshots for screenshots.
- The audience is Edoardo first and others later, with WCAG AA contrast plus the keyboard as the accessibility bar
  (decision 27).

## 3. Critique and audit

Status: **done**. The audit's fade bug is fixed, and the re-audit gives 16/20. What's left goes to steps 4, 5 and 7.
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
- Audit: 15/20 (Good), from the code, the snapshots measured pixel by pixel, and headless tests. It's saved in
  `.impeccable/audit/`, which isn't committed. Accessibility is scored against decision 27's bar.
  - **P1:** new rows fade in when a list on screen grows. The table adds them transparent and brings them to full
    opacity over ~200 ms. It happens on a backspace to a broader query, on ⌘K from a shorter list and on ⎋ back to a
    longer one, but not on ⌘P, where the list was hidden. It breaks "no animation", and the latency log calls the
    rows drawn while they're still transparent.
    **Fixed:** rows are added and removed with no animation (`insertRows`/`removeRows`), and
    `rowsAddedToAListOnScreenShowAtOnce` covers it. `make bench`, same session, before → after: keystroke update
    2.01–2.07 → 1.94–1.97 ms, ⌘P with the recent list 0.50–0.51 → 0.42–0.45 ms.
  - **P1:** in dark mode the selection is 2.66:1 against the panel, under the 3:1 of decision 27, and it's the only
    cue: selected and unselected titles are both white. A lighter fill alone can't fix it (#0A84FF is 4.6:1 against
    the panel, but white text on it only 3.7:1), so it needs a second cue. Step 4.
  - **P2:** the panel is square and has no edge in dark mode: its #1E1E1E runs to the border, the same color as dark
    windows behind it. Rounded corners need a non-opaque window, so step 4 decides and step 5 measures.
  - **P2:** a long ⌘K context is cut without an ellipsis ("Actions for Quarterly_Budget_Review_Final_Version_Approved"),
    losing the end of the name. It gets cut in the middle when step 4 moves it out of the placeholder.
  - **P3, outside the bar:** VoiceOver hears nothing as the selection moves, and the symbols ignore Increase Contrast.
  - Everything else passes AA in light and dark. The lowest text is the detail line on the light selection (4.71:1);
    the lowest symbol is 3.95:1 in light mode.
- Re-audit after the fade fix: 16/20 (Performance 3 → 4). Nothing in the panel animates any more: rows, the panel's
  size and keyboard scrolling all change in one frame. The two P2s and the dark-selection P1 remain, for step 4.
- Snapshot states for the review: `long-names` and `long-actions` are added. `running` and Open with… aren't: they
  use the same app rows as `recent`, and both would put the real apps on this Mac in the repo.

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
