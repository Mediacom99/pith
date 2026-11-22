---
name: Pith
description: A keyboard-only macOS launcher panel in the Stage direction - what Return acts on is always on the tile.
colors:
  window-background-light: "#FFFFFF"
  window-background-dark: "#1E1E1E"
  label-light: "rgba(0, 0, 0, 0.85)"
  label-dark: "rgba(255, 255, 255, 0.85)"
  quiet-light: "#666666"
  quiet-dark: "#A1A1A1"
  key-light: "#3C3C3C"
  key-dark: "#D6D6D6"
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
    textColor: "{colors.key-light}"
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

<!-- impeccable:design-map -->
Name: Pith
Colors: window-background-light #FFFFFF, window-background-dark #1E1E1E, label-light rgba(0, 0, 0, 0.85), label-dark rgba(255, 255, 255, 0.85), quiet-light #666666, quiet-dark #A1A1A1, key-light #3C3C3C, key-dark #D6D6D6 (+12 more in the frontmatter)
Fonts: SF Pro (search, tile-name, row-title, key-primary, key-secondary, return-mark, detail, tag, key-cap)
Spacing: key-cap-gap 4pt, label-gap 6pt, list-bottom 6pt, tile-margin 8pt, key-words-gap 8pt, key-line-gap 8pt, grid-inner 10pt, tile-icon-gap 14pt, tile-padding 16pt, tile-keys-gap 16pt, icon-x 18pt (+1 more in the frontmatter)
Radius: panel 14pt, tile 10pt, row 7pt, key-cap 5pt
North Star: "Stage"
Rules:
- The No-Accent Rule. Nothing in the panel is filled or tinted with the accent color or any brand hue.
- The Meaning-Only Rule. Red and orange appear only for Force Quit's confirmation and config problems.
- The Fill-Is-Not-Enough Rule. A low-contrast fill never carries state alone: the selected row ends in ↩ and the tile names the item.
- The 11 pt Floor Rule. No text is smaller than 11 pt.
- The Cut-in-the-Middle Rule. Names and folders that don't fit truncate in the middle, so both the start and the extension stay visible (`Quarterly_Bud…Review.pdf`).
- The One-Baseline Rule. Everything on a row (name, folder, "running", ↩) sits on the name's baseline.
- The Flat-Inside Rule. Only the panel casts a shadow, and it is the system's.
Don't:
- Don't fill the selection, a key or anything else with the accent color or a solid color bar.
- Don't use red or orange except for Force Quit's confirmation and config problems.
- Don't animate, fade, slide or blur anything; the panel appears and disappears in one frame.
- Don't use materials, vibrancy, translucency or Liquid Glass; the panel is opaque.
- Don't add shadows inside the panel.
- Don't set text below 11 pt, or use uppercase labels or letter-spacing for hierarchy.
- Don't hide what ⏎ does in a footer or leave it unsaid.
Do:
- Do show what ⏎ acts on in the tile, with the ⏎ key's words in semibold label color.
- Do end the selected row in ↩, and keep the selection a quiet fill (black 7 % light, white 10 % dark) with 7 pt corners, inset 8 pt.
- (+5 more)
Full: .impeccable/design-full.md (read a section when you need its detail)
