# Brief: the clipboard

The design brief for the clipboard (`FEATURES.md` §5), from `/impeccable shape` (design plan step 6). Milestone 3
builds from it. It adds to Stage (decision 29) and changes nothing in the launcher.

## 1. Job and audience

- Edoardo, mid-task in another app, needs something he copied a minute or an hour ago: usually one of the last few
  copies, sometimes a pinned snippet he reuses.
- He opens it with ⌘⇧V (decision 34), or types `c ` in the launcher. He looks at the rows and the preview, then
  presses ⏎, which pastes into the app he came from.
- He copies text (snippets, commands, code), links, images and screenshots, and files from Finder, all of them often.
- Mode: Operate.

## 2. Outcome and proof

- The usual path is ⌘⇧V, ↓, ⏎, and the item is pasted at the cursor.
- The row and the preview are enough to recognize the right item without reading it closely.
- The tile always says what ⏎ will do ("Paste", or "Copy" when Pith can't paste), so nothing is pasted by surprise.
- The `FEATURES.md` §1 targets hold:
  - ⌘⇧V → drawn in one frame;
  - a keystroke → results in under 5 ms;
  - nothing on the main thread waits for the disk.

## 3. Direction

Stage carries over unchanged: the tile shows what ⏎ acts on, the list is compact, the selection is quiet and ends in
↩, and color appears only for meaning.
- **The tile becomes the preview:** it grows from 92 pt to 188 pt, which is three rows' worth (92 + 3 × 32).
  - Five rows fit under it, and the panel keeps its 423 pt, so nothing moves while you move through the list.
  - The direction said 168 pt; 188 pt is what fits five whole rows.
- **The focal moment:** what ⏎ will paste, large on the tile, with "Paste ↩" and "Actions ⌘K" beside it.
- **Marking the mode:** the magnifier becomes `doc.on.clipboard` (same size, quiet gray), and the placeholder reads
  "Search clipboard".
- **One addition to the type:** SF Mono 12 pt, only for a plain text's preview.
  - It shows exactly what will be pasted: straight versus curly quotes, tabs, indentation.
  - Rich text previews in SF Pro 13 pt, since it pastes with its own fonts. Everything else stays SF Pro.
- **Every tile reads the same way** (step 9): what the clip is hangs from the top, keys included, and the line about
  when and where it was copied runs along the bottom, from the tile's left edge. It stays put as the selection goes
  from one kind to another; only an image, which fills the height, keeps it beside it.

## 4. Scope and boundaries

- **In scope:**
  - the clipboard mode of the panel (list, preview tile, search, ⌘K actions);
  - its empty, paused and permission states;
  - the launcher commands Pause / Resume Clipboard Recording and Clear Clipboard History.
- **Not in scope:**
  - the in-panel text editor and Edit Image (decisions 36, 40);
  - anything in the launcher's own modes.
- **Anti-goals:**
  - No network: no page titles or favicons for links, since the only network access is currency rates and the
    update check.
  - No grid or gallery of images.
  - No tabs, categories or filters by kind or app.
  - No animation.
  - No number keys for quick paste.
  - No settings window.

## 5. Each kind, in the row and on the tile

Rows keep the launcher's grid: 32 pt high, a 20 pt icon at 18 pt, text at 48 pt, and the end 18 pt from the right.
At the end of each row, where "running" sits in the launcher, is the age:
- "now" for the last minute, then "5 min", then "14:05" for today;
- "yesterday", then a weekday ("Mon"), then a date ("12 Nov").

A pinned item has `pin.fill` in quiet gray before its age. The selected row ends in ↩, as in the launcher.

**Text** (plain and rich):
- **Row:**
  - **Icon:** the app it was copied from (its source marker, else the frontmost app at copy time, even after a quick
    ⌘Tab), or `text.alignleft` when that's unknown.
  - **Title:** the first line that isn't blank, with whitespace collapsed and cut at the end. While searching, it's
    the first line that matches instead.
  - **Detail:** "12 lines" when there's more than one.
- **Tile:**
  - **Preview:** the text itself, from the tile's top-left, in SF Mono 12 pt (SF Pro 13 pt for rich text), label
    color. Up to 8 lines of about 70 characters, wrapped, with indentation kept; anything longer ends in "…".
  - **Under it:** one line in Detail, "Text · 12 lines · copied today at 14:05 from Terminal". Rich text says "Rich
    text", and a long text adds its size ("1.2 MB").
  - **Keys:** at the top right, level with the first line.
- **Edge case:** text that is only spaces or line breaks reads "Spaces and line breaks" in quiet gray.

**Links:**
- **Row:** the source app's icon (or `link`), then the URL without its scheme, cut in the middle
  (`github.com/acme/…/pull/42`).
- **Tile:** the launcher's tile layout, from the top.
  - a 48 pt icon of the source app;
  - the host as the name ("github.com");
  - the full URL in Detail, wrapped over up to 5 lines and cut in the middle beyond that;
  - along the bottom, "Link · copied today at 14:05 from Slack".
- **Opening it:** ⌘K → "Open in Safari" names the app that will open it (`[open_links]`, else the default browser),
  as "Open in Preview" does for files.

**Images** (screenshots too):
- **Row:**
  - **Icon:** a 20 pt thumbnail, filled and cropped to the square, with 4 pt corners.
  - **Title:** "Image".
  - **Detail:** "1920 × 1080".
- **Tile:**
  - **The image:** fitted into a box up to 156 pt high and 320 pt wide, with 6 pt corners, never scaled past its own
    pixels. A transparent image sits on a faint checkerboard of the tile and selection fills.
  - **Beside it:** "Image" (Tile Name), "1920 × 1080 · PNG · 2.1 MB", and "Copied today at 14:05 from Safari".
  - An animated GIF shows its first frame.

**Files** (copied in Finder):
- **Row:** the file's icon, its name cut in the middle, and its folder, exactly like a file row in the launcher.
- **Tile:** the launcher's file tile, from the top, with "PDF document · 2.1 MB · copied today at 14:05 from Finder"
  along the bottom.
- **Several files:** the row reads "Quarterly_Budget_Review.pdf and 2 more". The tile shows the first file's icon and
  name, their folder (or "3 folders"), then the other files' names one per line, up to 5 lines, the last "and 12 more"
  when they don't all fit; along the bottom, "3 files · 4.2 MB · copied …".
- **A file that's gone:** its folder line reads "No longer in ~/Documents/Acme".

**Quick Look:** ⌘Y, or Space with an empty field, previews an image or a file at full size, as in the launcher
(decision 20).

## 6. States

- **The list:**
  - Newest first, always (decision 33). When you type, pinned matches come first, then the rest newest first.
  - Copying something already in the history moves it to the top and keeps its pin. Pasting from the history does
    the same.
- **Opening it:** the newest item is selected. The panel opens in one frame with the five rows and the tile's
  preview already prepared.
- **Search:**
  - word by word, in any order, over text, URLs and file names;
  - no matches collapses the panel to the search bar, as in the launcher.
- **No history yet** (first run, or after Clear):
  - the tile shows `doc.on.clipboard` at 48 pt in quiet gray;
  - "Nothing copied yet";
  - "Copy text, a link, an image or a file and it shows up here";
  - along the bottom, the keys that will act on a clip, as configured: "↩ pastes the one you pick · ⌘K shows its
    actions · ⌃⌥V pastes the last one, then the one before" (a key that's off isn't named);
  - no keys on the right and no rows: there's nothing to act on yet.
- **Recording paused:**
  - the first row reads "Recording is paused", with `pause.circle` in quiet gray, and ⏎ on it resumes;
  - quiet, not orange: it's a state you chose, not a problem.
- **No Accessibility access** (pasting needs it):
  - The first ⏎ asks macOS for it. Until it's granted:
    - the tile's first key reads "Copy";
    - ⏎ puts the item on the clipboard and closes;
    - the first row is a problem row, "Paste needs Accessibility access", and ⏎ on it opens the setting.
  - This widens orange's one meaning from "config problem" to "a setup problem you fix with ⏎". The Meaning-Only
    Rule in `DESIGN.md` gets that wording.
- **⌘K actions**, in this order, filtered as in the launcher:
  - Paste (⏎)
  - Copy to Clipboard
  - Paste as Plain Text (rich text only)
  - Open in … (links)
  - Reveal in Finder (files)
  - Save as File (text, images): to Downloads with a dated name, then a notification that reveals it (decision 39)
  - Pin / Unpin
  - Delete
  - The item stays on the tile; the first key names the selected action, and the second becomes "Back esc".
- **Delete:**
  - immediate for an unpinned item, from ⏎ on its row;
  - a pinned one asks for a second ⏎ in red, as Force Quit does (decision 28): "Press ⏎ again to delete this pinned
    clip";
  - from its shortcut (⌘T for a text), any one asks the same way (decision 74): "Press ⏎ again to delete this clip".
- **Clear Clipboard History** (a launcher command) asks for a second ⏎ the same way: "Press ⏎ again to clear the
  clipboard history". Pinned items stay.
- **A failure after the panel closes** (paste, save, reveal) posts a notification, as decision 32 does for the
  launcher.

## 7. Moving between modes

- ⌘⇧V opens the panel in clipboard mode, switches to it from the launcher, and closes the panel when it's already in
  clipboard mode. ⌘P switches back to the launcher.
- `c ` as the whole query in the launcher switches to clipboard mode. The field empties and the clipboard symbol
  replaces the magnifier.
- ⌫ on the empty field goes back to the launcher. ⎋ closes the panel; inside ⌘K, ⎋ steps back first.
- Switching modes changes the tile's height and the number of rows in one frame, without animation. The panel's own
  size never changes.

## 8. Constraints

- **Speed:**
  - Thumbnails are rendered once at copy time, off the main thread, at exact pixel sizes: 40 px for rows, and the
    preview box at 2x. Never the full image.
  - The newest items' rows and previews are kept ready in memory, so ⌘⇧V draws without touching the disk.
  - Search runs over keys prepared at copy time, held in memory: text content lowercased and capped per item. It
    must stay under 5 ms across a month of history (thousands of items).
  - The text preview lays out only its first 8 lines.
- **Accessibility:**
  - AA contrast in light and dark, as everywhere.
  - Each row has a VoiceOver label: "Text from Terminal, docker compose up, 12 lines, copied at 14:05, pinned";
    "Image, 1920 by 1080".
- **Reused:** the tile, keys and key caps, rows, the selection and ↩, problem rows, the second-⏎ confirmation, the ⌘K
  list and filter, Quick Look, and notifications.

## 9. Decided with the milestone plan

`docs/MILESTONE-3.md` builds this.
- Retention is 2 GB and 30 days (decision 37).
- Transient and auto-generated copies are skipped too (decision 38).
- Save as File goes to Downloads (decision 39).
- Edit Image comes after milestone 3, with the editor (decision 40).
- Storage is SQLite, and copies are watched on a timer whose cost step 8 measures.
- A stable signing identity keeps the Accessibility grant across reinstalls (step 5).
