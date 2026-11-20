---
version: 1
slug: "sources-launcher-launcherpanel-swift"
primary_target: "Sources/Launcher/LauncherPanel.swift"
related_targets: ["Sources/Launcher/LauncherViewController.swift","Sources/Launcher/ResultViews.swift"]
---

# Launcher panel

Scope: the launcher panel and its modes: search, the empty state, ⌘K actions and Open With…, the calculator's answer,
and the clipboard browser. Mode: Operate.

Job: a few letters, a glance, ⏎, from inside another app. What binds the look: an opaque window, no motion or blur,
fixed frames, and the speed targets.

Chosen direction: Stage (decision 29). The memorable moment: whatever ⏎ will act on sits on the tile, large, with
the words for ⏎ and ⌘K beside it.

Unresolved:
- The clipboard's in-panel text editor (design plan step 6).

## Direction contract

THESIS: What ⏎ will act on is always on stage. A tile under the search bar shows the selected item large, where it is
and what it is, with the keys for ⏎ and ⌘K; the list under it is compact. It refuses the category's default: a solid
accent selection bar, with what ⏎ does hidden in a footer or nowhere.

OWN-WORLD: System neutrals in light and dark, with quiet low-opacity fills (tile about 4 %, selection about 7–10 %)
and no accent-colored fills. Color only for meaning: red for Force Quit, orange for a config problem. SF Pro, SF
Symbols, the system's own icons. Keys are words beside small filled key caps. Corners: panel 14 pt, tile 10 pt,
rows 7 pt; a 1 pt edge (black 12 % light, white 14 % dark).

STORY: You type a few letters, see on the tile what ⏎ will open, copy or paste and where it lives, and press ⏎. Or
you press ⌘K: the item stays on the tile while the list becomes its actions, and you filter them.

FIRST VIEWPORT: 680 pt wide. Search bar 52 pt: magnifier, 20 pt query. Tile 92 pt, inset 8 pt: 48 pt icon, name 19 pt
semibold, folder and kind with last opened at 12 pt, keys on the right ("Open ↩" in bold, "Actions ⌘K"). Then 8 rows
of 32 pt: 20 pt icon, name 14 pt and folder 12 pt on one line; the selected row has the quiet fill and a ↩ at its end.
In the clipboard the tile grows to 168 pt and becomes the preview.

FORM: Stage, Claude's own direction, after Edoardo turned down the roll's assignment (Tokyo rail signage) and asked for
"a completely original new one"; seed: 47a00053a3e03fc9 (assignment declined). Chosen: "ok lets go with stage visual
drection".

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
