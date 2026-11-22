# Design plan

Goal: a deliberate look for every surface in `FEATURES.md`, done through the impeccable skill (decisions 24–27).

- **Surfaces already built:** the search bar; the app, file, folder and command rows; the empty states; the ⌘K
  actions and Open with…; config problems. These get the new design.
- **Surfaces still to build:** the calculator row (§6); the clipboard browser with its preview pane, pinned items and
  in-panel text editor (§5). These get a design brief that their milestones build from.
- **What doesn't change:** the speed targets (one frame from ⌘P, under 5 ms per keystroke), and an opaque panel with
  no animation and no blur.

This plan runs alongside the milestone plans. Step 7 comes before step 6, and step 6 starts with the clipboard,
milestone 3 (decision 31).

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

Status: **done**: Edoardo picked Stage (decision 29).
- Claude drew four directions as local HTML mockups: Native Tahoe, rofi-dense, Raycast-like, and Stage, Claude's own.
  Each showed a search, ⌘K on a long name while filtering, the calculator's answer on top of the results and the
  clipboard, at real size in light and dark, with the system's icons and Tahoe's colors sampled from the snapshots.
- Each answered the critique's two design findings and the audit's three open ones: where the ⌘K context lives while
  you filter, how the panel shows what ⏎ and ⌘K do, a dark selection with a second cue at 3:1, and the corners and
  dark-mode edge.
- Along the way Edoardo turned down impeccable's roll for the fourth (Tokyo rail signage) and asked for an original
  one, and turned down the solid blue selection for Raycast's quiet, low-opacity fills.
- Stage: a tile under the search bar shows what ⏎ will act on (the item, the calculator's answer, the clipboard
  preview) with the keys for ⏎ and ⌘K, over a compact list. The selected row has a quiet fill and ends in ↩. Color
  only for meaning: red for Force Quit, orange for a config problem.
- The mockup stays in `.impeccable/directions/index.html` (not committed) as step 5's reference, with ten Stage states:
  the four above plus the empty state, a file on the tile, Open With…, Force Quit's second ⏎, a config problem and an
  image in the clipboard. It's deleted when step 5 is done.
- The direction contract is in `.impeccable/surfaces/` (committed), for impeccable's later passes.
- `docs/DESIGN.md` moves to step 5: impeccable writes it from the built panel, not from the mockup, so it describes
  what's true.

## 5. The launcher in the new design

Status: **done**. Stage is built, reviewed, documented and installed.
- Built: the 52 pt bar, the tile (what ⏎ acts on, with its keys), 8 compact rows of 32 pt with the folder after the
  name, the quiet selection ending in ↩, ⌘K and Open With… keeping the item on the tile, Force Quit in red, config
  problems in orange, and 14 pt corners with a 1 pt edge. The values are in the Visual decisions table, and the system
  in `docs/DESIGN.md`.
- This closes step 3's open findings: the dark selection (↩ at 8.4:1, and the tile names the item), the dark-mode
  edge, the ⌘K context (on the tile, cut in the middle) and the ⏎/⌘K hints (the tile's keys).
- Contrast, measured on the snapshots: quiet text 4.75:1 at worst (the folder on the dark selection), ↩ 9.4:1 light
  and 8.4:1 dark, Force Quit's red 4.7:1 and 4.9:1, the problem's orange 4.9:1. The quiet gray is opaque: text fields
  drew the translucent version at #272727 instead of #666666.
- Speed, `make bench`, same session, before → after: keystroke update 1.89 → 2.00–2.07 ms; ⌘P with the recent list
  0.38 → 0.39–0.50 ms. Drawing the panel's and the tile's rounded backgrounds on the CPU first cost +1.4 ms per
  keystroke (the panel repaints when it grows or shrinks); as layer properties they cost nothing.
- On screen (`make logs`): ⌘P → drawn 23 ms (one sample; ~27 ms on the milestone 2 build), so the clear window and its
  corners cost nothing measurable and stay (decision 29). Keystrokes 7–12 ms, as before.
- Memory: 39 MB 25 s after launch, against 30 MB for the milestone 2 build measured the same way. 5.9 MB of it is the
  tile's 96 px icons, one per app, each in its own 48 KB block. Under the 50 MB target, so Edoardo kept them
  rendered ahead of time: rendering on demand would save ~5 MB but could show a result's big icon a frame late.
- Impeccable's finish review: three fixes (the Force Quit row's ↩ in red, the problem tile's copy, the reason for the
  fixed height), then "ship". `docs/DESIGN.md` and `.impeccable/design.json` were written from the build.
- Tests: `theTileShowsWhatReturnActsOn`, `onlyTheSelectedRowEndsInReturn`, `saysWhenAnItemWasLastOpened`,
  `theTileSplitsAProblemIntoTitleAndSentence`, `History.lastOpened`. The snapshots use a fixed clock, so "opened today
  at 14:05" doesn't change them; the problem snapshot selects the problem, to show its tile.

## 6. Briefs for the planned surfaces

Status: **todo**.
- Run `/impeccable shape` for the calculator row, the clipboard browser (list, preview pane, pinned items) and the
  text editor.
- Their milestone plans point to the briefs.

## 7. Polish

Status: **in review**. Polish, clarify and harden passes are done, and the snapshots are final for the launcher.
- **Harden:** an action that fails after the panel closes posts a notification saying what failed and why, and a
  click reveals the item (decision 32): Move to Trash, opening a file, folder or app, Open With…, Open in Terminal.
  A failed Move to Trash keeps the item in the history. `Notifier` (was `ZipNotifier`) posts these and Zip's.
  Tested by `aFailedMoveToTrashIsReported`, on a file that doesn't exist, so nothing reaches the Trash.
- **Copy:**
  - Escape's key cap reads "esc", as on the keyboard: ⎋ at 11 pt read as an undo arrow.
  - Commands say "Pith command" on the tile, not "Launcher command".
  - Problems say what Pith does meanwhile: a config that isn't valid TOML adds "so every setting is at its
    default", a taken hotkey "so it's still "cmd+p"". An app that doesn't resolve reads "can't find the app "…""
    instead of "no app "…"".
  - Kept: "Search" as the placeholder (the calculator and the `c ` prefix join the root search, so "Search apps and
    files" would go stale), and the action names, which are Finder's.
- **Contrast**, measured on the snapshots: the key caps' glyphs were 4.1:1 in dark mode, under AA. They now use a
  Key color shared with the row's ↩ (#3C3C3C light, #D6D6D6 dark): 8.8:1 and 7.4:1 on a cap. Everything else
  passes: the placeholder 10.4:1 and 10.9:1, "running" 5.7:1 and 6.5:1, and the step 5 numbers.
- Not run on screen: the notifications, which need a real failure in the running app.
