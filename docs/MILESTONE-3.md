# Milestone 3: the clipboard

Goal: Pith keeps a history of what you copy and pastes any of it back from the keyboard: ⌘⇧V, a glance, ⏎ (decision
31). It records text, links, images and files, opens in one frame, searches in under 5 ms per keystroke, and stays
under 50 MB idle. The design is `docs/BRIEF-CLIPBOARD.md`. Two pieces of `FEATURES.md` §5 come later: the in-panel
text editor and Edit Image (decisions 36, 40).

Status values: **done**, **in review** (built and tested, waiting for Edoardo), **in progress**, **todo**.

## 1. Storage and retention

Status: **done** (core library; the app uses it from step 2).
- `ClipboardStore` keeps the history in `~/Library/Application Support/pith/clipboard/`:
  - a SQLite database (the system library) holding the entries and their text;
  - images as files beside it;
  - thumbnails rendered once with ImageIO at their exact pixel sizes (40 px for rows, the preview box at 2x).
- Each entry records:
  - its kind (text, rich text, link, image, files);
  - the pasteboard types it came with (the standard ones, step 2), so a paste puts them all back;
  - the source app, the time, a pin, and its size.
- **Retention:**
  - 2 GB and 30 days by default (decision 37), oldest unpinned first; pins are never dropped.
  - Applied after each copy and at launch, so no timer is needed.
- Every call runs on the store's own serial queue, `launcher.clipboard`, so it's off the main thread and off Swift's
  cooperative pool. The main actor gets ready-made `Clip` values.
- In memory, a clip keeps only the first 4,096 characters of its text; the rest stays on disk for the paste.
- Duplicates are matched by a SHA-256 of the kind, every representation and the image.
- Deleting gives the space back to the disk: incremental vacuum for the database, and the image files are removed.
  On load, image files a crash left without their clip are removed too.
- Covered by 12 tests on temporary folders, never the real `~/Library/Application Support/pith/`:
  - newest-first loading;
  - duplicates moving to the top with their pin;
  - representations coming back in order;
  - thumbnail sizes, including a small image that isn't scaled up;
  - retention by age, then size, keeping pins;
  - delete, clear, relaunch, long text, and leftover files.

## 2. Recording

Status: **in review**. Built and tested on a private pasteboard. The installed app records from launch, but the
history can't be seen until step 4 shows it.
- **Watching:** `ClipboardRecorder` runs a GCD timer on its own queue, `launcher.clipboard.watch`, because macOS has
  no notification for a new copy.
  - Every 0.5 s it reads the pasteboard's change count, with 0.25 s of leeway so the system can coalesce wakeups.
  - It stops while the screens sleep or another user's session is in front. Step 7 measures what it costs at idle.
  - What's on the clipboard at launch isn't recorded, so starting Pith never reads the clipboard by itself.
- **Clipboard permission:** macOS can ask before an app reads the clipboard (`accessBehavior`, since 15.4).
  - "Ask" (or never asked yet): the copy is read, and macOS may ask Edoardo the first time.
  - "Never": nothing is read, and the log says so once. Step 4 shows it in the panel.
- **Skipped:** copies with a concealed, transient or auto-generated marker (decisions 35, 38). Only the types are
  read for this check, so a password's data is never fetched.
- **What's read:** only the standard types apps paste with:
  - plain text (UTF-8, UTF-16);
  - rich text (RTF, RTFD, HTML);
  - links (`public.url` and its title);
  - file URLs;
  - images (PNG, TIFF, JPEG, HEIC).

  Other types aren't read at all, because reading one makes the app that copied render it, and apps like
  spreadsheets offer many large ones. Pasting puts back the standard types, not an app's private format.
- **Classifying** (`ClipReading`, core library):
  - files win over everything, since Finder's copies also carry the name as text and the icon as an image;
  - an image counts only without text (screenshots, Copy Image), and is converted to PNG unless it already is one;
  - text that is one URL (http, https, mailto, ftp, ssh…) is a link;
  - text with RTF or HTML is rich text, and rich text with no plain text gets the pasteboard's conversion;
  - a copy with none of these is skipped.
- **Source:** the app named by the copy's `org.nspasteboard.source` marker, otherwise the app in front.
- **Duplicates:** a copy that is already in the history moves that clip to the top, keeping its pin. An unknown
  source doesn't overwrite a known one, so pasting from the history won't record "from Pith".
- **Old history** is pruned to 2 GB and 30 days at launch and after each copy.
- **Tests:**
  - 10 on classifying.
  - 6 on the recorder, on a private named pasteboard, so they never read or change your clipboard. They cover:
    source; nothing at launch; passwords and temporary copies skipped; files, images and links; RTF-only text; a
    paste from the history moving instead of duplicating.

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
