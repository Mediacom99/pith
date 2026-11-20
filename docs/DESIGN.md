---
name: launcher
description: A keyboard-only macOS launcher panel in the Stage direction - what Return acts on is always on the tile.
colors:
  window-background-light: "#FFFFFF"
  window-background-dark: "#1E1E1E"
  label-light: "rgba(0, 0, 0, 0.85)"
  label-dark: "rgba(255, 255, 255, 0.85)"
  quiet-light: "#666666"
  quiet-dark: "#A1A1A1"
  tile-fill-light: "rgba(0, 0, 0, 0.035)"
  tile-fill-dark: "rgba(255, 255, 255, 0.045)"
  selection-fill-light: "rgba(0, 0, 0, 0.07)"
  selection-fill-dark: "rgba(255, 255, 255, 0.10)"
  edge-light: "rgba(0, 0, 0, 0.12)"
  edge-dark: "rgba(255, 255, 255, 0.14)"
  danger-light: "#D70015"
  danger-dark: "#FF6961"
  danger-fill-light: "rgba(255, 59, 48, 0.10)"
  danger-fill-dark: "rgba(255, 69, 58, 0.16)"
  warning-light: "#C93400"
  warning-dark: "#FF9F0A"
typography:
  search:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "20pt"
    fontWeight: 400
  tile-name:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "19pt"
    fontWeight: 600
  row-title:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "14pt"
    fontWeight: 400
  key-primary:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13pt"
    fontWeight: 600
  key-secondary:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13pt"
    fontWeight: 400
  return-mark:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "13pt"
    fontWeight: 600
  detail:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "12pt"
    fontWeight: 400
  tag:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11pt"
    fontWeight: 400
  key-cap:
    fontFamily: "SF Pro, -apple-system, system-ui"
    fontSize: "11pt"
    fontWeight: 500
rounded:
  panel: "14pt"
  tile: "10pt"
  row: "7pt"
  key-cap: "5pt"
spacing:
  key-cap-gap: "4pt"
  label-gap: "6pt"
  list-bottom: "6pt"
  tile-margin: "8pt"
  key-words-gap: "8pt"
  key-line-gap: "8pt"
  grid-inner: "10pt"
  tile-icon-gap: "14pt"
  tile-padding: "16pt"
  tile-keys-gap: "16pt"
  icon-x: "18pt"
  text-x: "48pt"
components:
  panel:
    backgroundColor: "{colors.window-background-light}"
    rounded: "{rounded.panel}"
    width: "680pt"
    height: "52pt / 423pt"
  search-field:
    textColor: "{colors.label-light}"
    typography: "{typography.search}"
    height: "52pt"
  tile:
    backgroundColor: "{colors.tile-fill-light}"
    textColor: "{colors.label-light}"
    typography: "{typography.tile-name}"
    rounded: "{rounded.tile}"
    padding: "0 16pt"
    height: "92pt"
  row:
    textColor: "{colors.label-light}"
    typography: "{typography.row-title}"
    padding: "0 18pt"
    height: "32pt"
  row-selected:
    backgroundColor: "{colors.selection-fill-light}"
    textColor: "{colors.label-light}"
    rounded: "{rounded.row}"
    height: "32pt"
  row-danger:
    backgroundColor: "{colors.danger-fill-light}"
    textColor: "{colors.danger-light}"
    rounded: "{rounded.row}"
    height: "32pt"
  key-cap:
    backgroundColor: "{colors.selection-fill-light}"
    textColor: "{colors.quiet-light}"
    typography: "{typography.key-cap}"
    rounded: "{rounded.key-cap}"
    height: "20pt"
    width: "20pt"
  key-primary:
    textColor: "{colors.label-light}"
    typography: "{typography.key-primary}"
  key-secondary:
    textColor: "{colors.quiet-light}"
    typography: "{typography.key-secondary}"
---

# Design System: launcher

## Overview

**Creative North Star: "Stage"**

The panel answers one question before you press ⏎: what will it act on? A tile under the search bar shows the selected item large, with its icon, name, folder and kind, and the keys for ⏎ and ⌘K on its right. The list under it is compact. In ⌘K and Open With… the item stays on the tile while the list becomes its actions or apps, and the tile's first key names the selected one.

Everything else is quiet. The panel is the system window color, the tile and the selection are low-opacity fills of the label color, and nothing is filled with the accent color. Color appears only where it means something: red for Force Quit waiting for its second ⏎, orange for a config problem. Type is SF at fixed point sizes, icons are the system's own app and file icons and SF Symbols. The panel never animates, blurs or goes translucent; it appears in one frame and stays still.

Light and dark follow the system. Each custom color is a light/dark pair in `Sources/Launcher/Palette.swift`; every other color is an AppKit semantic color (`windowBackgroundColor`, `labelColor`, `secondaryLabelColor`, `placeholderTextColor`, the separator).

**Key Characteristics:**
- A 92 pt tile that always shows what ⏎ acts on, with its keys spelled out.
- Compact 32 pt rows on one line: icon, name, folder.
- Quiet fills (3.5–4.5 % tile, 7–10 % selection) instead of an accent bar.
- The selected row ends in ↩, so the selection never relies on its fill.
- Color only for meaning: red for danger, orange for a problem.
- Opaque, still, fixed geometry: no motion, no blur, no layout shift while typing.

## Colors

System neutrals carry the panel; four custom pairs add quiet fills and two meaning colors.

### Primary

The panel has no brand or accent color. The role of "primary" is held by the label color on the tile's first key ("Open", in bold), not by a hue.

### Neutral
- **Window Background** (light `window-background-light`, dark `window-background-dark`): `NSColor.windowBackgroundColor`, the panel's only surface. The hex values are what the snapshots render on macOS 26; the semantic color is what the code uses.
- **Label** (`label-light`, `label-dark`): `NSColor.labelColor`. Names, the query, the tile's name and its first key.
- **Secondary Label**: `NSColor.secondaryLabelColor`. The ↩ at the end of the selected row (9.4:1 light, 8.4:1 dark on the selection).
- **Placeholder**: `NSColor.placeholderTextColor`. "Search", "Filter actions", "Filter apps".
- **Quiet Gray** (`quiet-light` #666666, `quiet-dark` #A1A1A1): opaque, between the secondary and tertiary label colors. Folders, kinds, "running", the second key's words, key-cap glyphs, the magnifier and every SF Symbol in the list. 4.9:1 light and 4.75:1 dark on the selection, its darkest background.
- **Tile Fill** (`tile-fill-light`, `tile-fill-dark`): the tile's background. Rendered #F6F6F6 light and #282828 dark over the window.
- **Selection Fill** (`selection-fill-light`, `selection-fill-dark`): the selected row and the key caps. Rendered #EDEDED light and #353535 dark. On its own it is 1.2:1 light and 1.4:1 dark against the window.
- **Edge** (`edge-light`, `edge-dark`): the panel's 1 pt border in both appearances, which keeps it apart from a window of the same color behind it.
- **Separator**: the system separator, 1 pt, full width, under the search bar.

### Meaning
- **Danger Red** (`danger-light` #D70015, `danger-dark` #FF6961): Force Quit waiting for its second ⏎: its row's text, symbol and ↩, and the tile's first key. 4.7:1 light and 4.9:1 dark on its fill.
- **Danger Fill** (`danger-fill-light`, `danger-fill-dark`): the system red, faint, as that row's selection.
- **Warning Orange** (`warning-light` #C93400, `warning-dark` #FF9F0A): a config problem's symbol, in the row and on the tile. Darker than the system orange in light mode, which is 2.2:1 on white.

### Named Rules
**The No-Accent Rule.** Nothing in the panel is filled or tinted with the accent color or any brand hue. The selection is a gray fill plus ↩.

**The Meaning-Only Rule.** Red and orange appear only for Force Quit's confirmation and config problems. A new hue needs a new meaning first.

**The Fill-Is-Not-Enough Rule.** A low-contrast fill never carries state alone: the selected row ends in ↩ and the tile names the item.

## Typography

**Font:** SF Pro, the system font (`NSFont.systemFont`), at fixed point sizes. There is no second family and no monospace.

**Character:** One family at a few sizes; hierarchy comes from size, semibold weight and the quiet gray, never from case or tracking.

### Hierarchy
- **Search** (400, 20 pt): the query and its placeholder.
- **Tile Name** (600, 19 pt): the selected item's name on the tile.
- **Row Title** (400, 14 pt): each row's name, and action and app names in ⌘K.
- **Key Primary** (600, 13 pt): what ⏎ does, on the tile ("Open", "Open in Finder", "Open in Preview" in Open With…, "Open Config", "Run", "Force Quit").
- **Key Secondary** (400, 13 pt, quiet gray): "Actions", "Back", "Cancel".
- **Return Mark** (600, 13 pt, secondary label): the ↩ at the end of the selected row.
- **Detail** (400, 12 pt, quiet gray): the folder after a row's name; the tile's folder and kind lines.
- **Tag** (400, 11 pt, quiet gray): "running" at the end of a running app's row.
- **Key Cap** (500, 11 pt, quiet gray): the glyph inside a key cap (↩, ⌘, K, ⎋).

### Named Rules
**The 11 pt Floor Rule.** No text is smaller than 11 pt.

**The Cut-in-the-Middle Rule.** Names and folders that don't fit truncate in the middle, so both the start and the extension stay visible (`Quarterly_Bud…Review.pdf`).

**The One-Baseline Rule.** Everything on a row (name, folder, "running", ↩) sits on the name's baseline.

## Layout

The panel is 680 pt wide and has two heights. With no results it is only the 52 pt search bar. With results it is 423 pt: the bar, a 1 pt separator, the 92 pt tile with an 8 pt margin on every side, 8 rows of 32 pt, and 6 pt under the last row. It keeps 423 pt with fewer rows, so the tile, keys and rows never move while you type. The top edge stays fixed when it grows or shrinks.

It opens on the screen under the pointer: the expanded panel would be centered there, and the search bar is its top edge.

**One grid.** Row icons (20 pt) start 18 pt from the panel's side, 10 pt inside the selection. The magnifier (a 16 pt symbol in a 20 pt box) is centered on that column. Names and the query start at 48 pt, 10 pt after the icons, and stop 18 pt from the right side, 10 pt inside the selection.

**The tile.** Inset 8 pt from the panel's sides, the same inset as the selection, so their edges line up. Inside: 16 pt padding, a 48 pt icon, 14 pt to the text block, and at least 16 pt between the text and the keys. Its lines (name, folder, kind) are stacked 1 pt apart and centered on its height, as are the icon and the keys.

**Rows.** Name, then 6 pt, then the folder. A folder takes at most 38 % of the room when the name is too long for both. From the right: ↩ on the selected row, then 12 pt, then "running".

All views that change per keystroke use fixed frames, not Auto Layout.

## Elevation & Depth

The panel is one opaque surface with the system window shadow (`hasShadow`) and a 1 pt edge. Inside it there are no shadows: depth is tonal, the tile one faint fill above the window and the selection and key caps one step darker. No material, vibrancy, blur or translucency anywhere.

### Named Rules
**The Flat-Inside Rule.** Only the panel casts a shadow, and it is the system's. Nothing inside the panel is lifted.

## Shapes

Continuous (squircle) corners on the panel and tile, nested by size: panel 14 pt, tile 10 pt, selection 7 pt, key caps 5 pt. The only stroke is the panel's 1 pt edge; the tile, rows and caps have fills and no borders. The separator under the bar runs edge to edge.

## Components

### Panel
- **Surface:** window background, 14 pt continuous corners, 1 pt edge (Edge), system shadow. The fill, corners and edge are layer properties, so resizing repaints nothing.
- **States:** bar only (52 pt) or expanded (423 pt). It appears and disappears with no transition.

### Search Field
- **Style:** borderless, no background, no focus ring, 20 pt, the magnifier in quiet gray on its left.
- **Placeholder:** "Search"; "Filter actions" in ⌘K; "Filter apps" in Open With…. The placeholder says only what is being filtered; the item is on the tile.

### Tile (signature component)
What ⏎ acts on, always visible when there are results.
- **Shape:** 92 pt high, 10 pt corners, Tile Fill, no border.
- **Content:** a 48 pt icon; the name (Tile Name); the folder (Detail); the kind with when it was last opened ("PDF document · opened today at 14:05", "Application · running") (Detail). Lines that are empty are left out and the rest re-centered.
- **Commands:** their SF Symbol at 48 pt in quiet gray, "Launcher command" as the folder line, and "Run" as the only key.
- **Config problem:** the orange triangle, "Config problem, line 3" as the name, "Unknown setting "theme"" as the folder line, `~/.config/launcher/config.toml` as the kind line, and "Open Config" as the only key.
- **⌘K and Open With…:** the item stays; the first key becomes the selected action ("Reveal in Finder") or "Open in Preview", and the second becomes "Back ⎋".

### Keys
- **Layout:** one key per line on the tile's right, right-aligned, 8 pt between lines: words, 8 pt, then key caps 4 pt apart.
- **Key caps:** Selection Fill, 5 pt corners, 20 pt high and at least 20 pt wide (5 pt padding each side), the glyph in Key Cap type.
- **First key:** what ⏎ does, in Key Primary, label color; red in Force Quit's confirmation.
- **Second key:** "Actions ⌘ K" for items, "Back ⎋" one level down, "Cancel ⎋" in Force Quit's confirmation; Key Secondary in quiet gray. Commands and problems have no second key.

### Rows
- **Style:** 32 pt, one line: a 20 pt icon, the name (Row Title), the folder (Detail, quiet gray). A running app ends in "running" (Tag).
- **Selected:** a Selection Fill rounded rectangle (7 pt corners) inset 8 pt from the panel's sides, and ↩ at its end in Return Mark. It is drawn by the row view, never emphasized, so text keeps its colors.
- **Force Quit confirmation:** after the first ⏎ the row reads "Press ⏎ again to force quit Finder", its text, symbol and ↩ in Danger Red on Danger Fill, and the tile's first key turns red. ⎋, typing or moving the selection puts it back.
- **Config problem:** first in the empty state, "Config problem, line 3: unknown setting "theme"", with the orange triangle as its icon. ⏎ opens the config file.
- **Scrollers:** overlay only.

### Icons and Symbols
- **Apps and files:** the system's own icons, following the system icon style (Default, Dark, Clear, Tinted), rendered once at the exact pixel size: 20 pt in rows, 48 pt on the tile.
- **SF Symbols,** regular weight, drawn at 62 % of the icon box in quiet gray:
  - Commands: `gearshape` (Open Config), `arrow.clockwise` (Reload Config), `power` (Quit Launcher).
  - Actions: `arrow.up.forward.app` (Open, Open in Finder), `folder` (Reveal in Finder), `link` (Copy Path), `square.grid.2x2` (Open With…), `terminal` (Open in Terminal), `doc.on.doc` (Copy File, Copy Folder), `doc.zipper` (Zip), `trash` (Move to Trash), `xmark.circle` (Quit), `xmark.octagon` (Force Quit).
  - Problems: `exclamationmark.triangle`, in Warning Orange.
  - Search: `magnifyingglass`, 16 pt, quiet gray.

### Planned surfaces
The clipboard browser and the calculator are not built. Both extend the tile: in the clipboard the tile grows (168 pt in the direction) and becomes the preview; for the calculator it shows the answer that ⏎ will copy. They use the same fills, type and keys.

## Do's and Don'ts

### Do:
- **Do** show what ⏎ acts on in the tile, with the ⏎ key's words in semibold label color.
- **Do** end the selected row in ↩, and keep the selection a quiet fill (black 7 % light, white 10 % dark) with 7 pt corners, inset 8 pt.
- **Do** use the system semantic colors for surfaces and text, and Palette's quiet gray (#666666 / #A1A1A1) for everything secondary.
- **Do** keep every element on the shared grid: icons at 18 pt, text at 48 pt, 18 pt from the right.
- **Do** keep the panel's height fixed at 423 pt with results, however many rows there are.
- **Do** use SF Symbols in regular weight, in quiet gray, for anything that has no app or file icon.
- **Do** check text and meaningful symbols against WCAG AA in light and dark, on the selection, its darkest background.

### Don't:
- **Don't** fill the selection, a key or anything else with the accent color or a solid color bar.
- **Don't** use red or orange except for Force Quit's confirmation and config problems.
- **Don't** animate, fade, slide or blur anything; the panel appears and disappears in one frame.
- **Don't** use materials, vibrancy, translucency or Liquid Glass; the panel is opaque.
- **Don't** add shadows inside the panel.
- **Don't** set text below 11 pt, or use uppercase labels or letter-spacing for hierarchy.
- **Don't** hide what ⏎ does in a footer or leave it unsaid.
