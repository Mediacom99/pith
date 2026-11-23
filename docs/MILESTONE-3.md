# Milestone 3: the clipboard

Goal: Pith keeps a history of what you copy and pastes any of it back from the keyboard: ⌘⇧V, a glance, ⏎ (decision
31). It records text, links, images and files, opens in one frame, searches in under 5 ms per keystroke, and stays
under 50 MB idle. The design is `docs/BRIEF-CLIPBOARD.md`. Two pieces of `FEATURES.md` §5 come later: the in-panel
text editor and Edit Image (decisions 36, 40).

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Storage and retention

Status: **todo**.
- `ClipboardStore` keeps the history in `~/Library/Application Support/pith/clipboard/`:
  - a SQLite database (the system library) holding the entries and their text;
  - images as files beside it;
  - thumbnails rendered once with ImageIO at their exact pixel sizes (40 px for rows, the preview box at 2x).
- Each entry records:
  - its kind (text, rich text, link, image, files);
  - the pasteboard types it came with, so a paste puts back everything it was copied with;
  - the source app, the time, a pin, and its size.
- **Retention:**
  - 2 GB and 30 days by default (decision 37), oldest unpinned first; pins are never dropped.
  - Applied after each copy and at launch, so no timer is needed.
- Every read and write runs on a worker; the main actor gets ready-made entries.
- Tests use temporary folders, never the real `~/Library/Application Support/pith/`.

## 2. Recording

Status: **todo**.
- **Watching:** a GCD timer reads the pasteboard's change count, because macOS has no notification for a new copy.
  - It starts at 0.5 s, with leeway so the system can coalesce wakeups.
  - It pauses while the screens sleep or the session is switched away.
  - Step 7 measures what it costs at idle.
- **What's read:** plain text, rich text (RTF, HTML), links, images (PNG, TIFF) and file URLs, plus the frontmost
  app as the source.
- **Skipped:** concealed, transient and auto-generated copies (decisions 35, 38).
- **Duplicates:** copying something already in the history moves that entry to the top and keeps its pin (matched by
  a hash of its content).
- **Tests** use a private named pasteboard, never the general one, so they never touch your clipboard.

## 3. History in memory and search

Status: **todo**.
- `ClipboardIndex` (core library) holds the entries newest first, with search keys prepared at copy time: the text
  lowercased and capped per item, the URLs and the file names.
- Search is word by word, in any order, with the existing matcher. Pinned matches come first, then the rest newest
  first (decision 33).
- A text row shows the first line that matches the query.
- `make bench`: under 5 ms per keystroke over 5,000 entries.

## 4. Clipboard mode in the panel

Status: **todo**. As in the brief, §3, §5 and §7.
- **Opening it:**
  - ⌘⇧V (`[hotkeys] clipboard`, decision 34) opens it, switches to it, or closes it;
  - `c ` as the whole query switches to it from the launcher;
  - ⌫ on the empty field goes back to the launcher.
- **What changes:** the clipboard symbol and "Search clipboard" in the bar, and the 188 pt tile as the preview.
  - Text shows in SF Mono.
  - Images fit their box.
  - Links and files use the launcher's tile layout.
- **Rows** are drawn per kind, with ages and pins.
- **States:** empty history and recording paused.
- **Speed:** the newest rows and previews are ready in memory, so ⌘⇧V draws without touching the disk.
- **Snapshots:** every kind and state, light and dark, with AA contrast measured on them.

## 5. Paste and the ⌘K actions

Status: **todo**.
- **⏎ pastes into the previous app:**
  - the panel closes, the entry goes back on the clipboard with all its types, and a ⌘V is posted as a CoreGraphics
    event;
  - this needs Accessibility access, and the first ⏎ asks for it;
  - until it's granted, the key reads "Copy" and a problem row opens the setting.
- **⌘K:**
  - Copy to Clipboard
  - Paste as Plain Text
  - Open in … (`[open_links]`, decision 16)
  - Reveal in Finder
  - Save as File (to Downloads with a dated name, then a notification, decision 39)
  - Pin / Unpin
  - Delete (a second ⏎ for a pinned item)
  - Quick Look (⌘Y)
- **Failures** post a notification (decision 32).
- **A stable signing identity:** macOS ties the Accessibility grant to the app's signature, and the ad hoc signature
  changes on every `make install`.
  - The fix is a self-signed certificate in the login keychain, used by `make app`.
  - I'll ask Edoardo before creating it, since it goes into his keychain.
- Tests cover which actions each kind gets and the second ⏎. Paste and the clipboard actions aren't exercised, so
  tests never type into your apps.

## 6. Commands and config

Status: **todo**.
- **Launcher commands:**
  - Pause Clipboard Recording and Resume Clipboard Recording;
  - Clear Clipboard History, after a second ⏎; pinned items stay.
- **Config:** `[hotkeys] clipboard`, `[clipboard] max_size_gb` and `max_age_days`, and `[open_links]`. Each is
  parsed, documented in the template, tested, and reported as a problem row when it's wrong.

## 7. Performance

Status: **todo**. Measured with a month-sized history (thousands of entries, a few hundred screenshots):
- ⌘⇧V → drawn;
- keystroke → drawn;
- idle CPU and wakeups with the recording timer;
- memory and threads (`make stats`).

The numbers go in this status line.

## 8. Design review

Status: **todo**.
- An impeccable critique and polish of clipboard mode against the brief, on the snapshots.
- `docs/DESIGN.md` is updated, through its full text, with:
  - the 188 pt tile;
  - the SF Mono preview;
  - orange for any setup problem.
- The values go in the Visual decisions table.
