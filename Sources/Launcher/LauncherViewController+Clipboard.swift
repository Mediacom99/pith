import AppKit
import LauncherCore

// MARK: The clipboard

extension LauncherViewController {
    /// The notices, then the clips matching `query` (newest first, pinned first once you type: decision 33), with
    /// the newest clip selected.
    func clipRows(matching query: String) -> (rows: [Row], selection: Int) {
        guard let clipboard else { return ([], 0) }
        let notices = query.allSatisfy(\.isWhitespace) ? clipboardNotices.map(Row.notice) : []
        let index = clipboard.index
        let clips = index.search(query, limit: Self.clipLimit).map { Row.clip(index.clips[$0]) }
        return (notices + clips, clips.isEmpty ? 0 : notices.count)
    }

    /// The clipboard is showing: access is checked again, copied files are looked at again, and the history is loaded
    /// again if another program changed it (decision 73). The list shows at once; a reload updates it after.
    func clipboardShown() {
        onShowClipboard()
        facts.markStale()
        if let clipboard { Task { await clipboard.reloadIfChangedElsewhere() } }
    }

    /// A new copy, or clips pinned or dropped: ready the newest images, and show the change if the clipboard is up.
    /// The clip you're on stays selected, so a copy that lands while you choose (the recorder sees it up to 0.75 s
    /// late) doesn't move ⏎ to another clip.
    func clipboardChanged() {
        guard let clipboard else { return }
        clipImages.preload(clipboard.index, store: clipboard.store)
        guard mode == .clipboard else { return }
        guard sublist == nil else {
            clipsChangedBehind = true
            return
        }
        let selected = tableView.selectedRow
        if keepSelection == nil, rows.indices.contains(selected), case .clip(let clip) = rows[selected] {
            keepSelection = (clip.id, selected)
        }
        refresh()
    }

    /// The app a text or link was copied from, or the kind's symbol when there's no such app; nil while it's looked up,
    /// so a row doesn't show the symbol, then the app.
    func sourceIcon(of clip: Clip, size: IconSize) -> CGImage? {
        if let source = clip.source, !icons.isMissing(bundleID: source) {
            return icons.icon(forBundleID: source, size: size)
        }
        return icons.symbol(clip.kind == .link ? Symbols.link : Symbols.text, size: size)
    }

    /// Source apps still being looked up, for snapshots to wait on.
    var isResolvingApps: Bool { icons.isResolvingApps }

    /// The tile for a clip (docs/BRIEF-CLIPBOARD.md §5): a text as it will paste, an image in its box, a link or files
    /// as an item. ⏎ pastes it, or copies it without Accessibility access.
    func tileContent(for clip: Clip) -> TileView.Content {
        let source = clip.source.flatMap { icons.appName(forBundleID: $0) }
        let now = now()
        let primary = canPaste ? "Paste" : "Copy"
        let actions = actionsKey
        switch clip.kind {
        case .text, .richText:
            let preview = ClipText.preview(of: clip)
            let size = clip.textBytes >= ClipText.longText ? ClipText.bytes(clip.textBytes) : ""
            return TileView.Content(
                name: "",
                kind: ClipText.about(
                    [ClipText.kindName(clip.kind), ClipText.detail(of: clip), size], copied: clip.copied, from: source,
                    now: now),
                primary: primary, secondary: actions,
                preview: .text(preview, isBlank: preview.allSatisfy(\.isWhitespace)))
        case .link:
            return TileView.Content(
                icon: sourceIcon(of: clip, size: .tile), name: ClipText.host(of: clip), place: clip.text,
                kind: ClipText.about(["Link"], copied: clip.copied, from: source, now: now), primary: primary,
                secondary: actions, placeLines: 3)
        case .image:
            let image = clipboard.flatMap { clipImages.preview(clip, store: $0.store) }
            let when = ClipText.copied(clip.copied, now: now) + (source.map { " from \($0)" } ?? "")
            return TileView.Content(
                name: "Image",
                place: "\(ClipText.detail(of: clip)) · PNG · \(ClipText.bytes(clip.size))",
                kind: when.prefix(1).uppercased() + when.dropFirst(), primary: primary, secondary: actions,
                preview: .image(image, size: ClipText.previewSize(of: clip)))
        case .files:
            let paths = ClipText.paths(of: clip)
            let known = paths.compactMap(facts.fact)
            let gone = paths.count == 1 && known.first?.exists == false
            let bytes = known.count == paths.count ? known.compactMap(\.bytes).reduce(0, +) : nil
            let first = paths.first.map { URL(filePath: $0) }
            let kind =
                paths.count > 1 ? "\(paths.count) files" : first.flatMap { icons.typeName(forFile: $0) } ?? ""
            return TileView.Content(
                icon: first.flatMap { icons.icon(forFile: $0, size: .tile) }, name: ClipText.title(of: clip).text,
                place: gone ? "No longer in \(ClipText.folders(of: clip))" : ClipText.folders(of: clip),
                kind: ClipText.about(
                    [kind, bytes.map(ClipText.bytes) ?? ""], copied: clip.copied, from: source, now: now),
                primary: primary, secondary: actions)
        }
    }

    /// What Clear Clipboard History's row says while it waits for its second ⏎.
    static let clearConfirmation = "Press ⏎ again to clear the clipboard history"

    static func noticeTitle(_ notice: ClipboardNotice) -> String {
        switch notice {
        case .paused: "Recording is paused"
        case .cannotRead: "Pith can't read the clipboard"
        case .needsAccessibility: "Paste needs Accessibility access"
        }
    }

    static func noticeTile(_ notice: ClipboardNotice, icon: CGImage?) -> TileView.Content {
        switch notice {
        case .paused:
            TileView.Content(
                icon: icon, name: noticeTitle(notice), place: "Copies aren't saved until you resume", primary: "Resume")
        case .cannotRead:
            TileView.Content(
                icon: icon, name: noticeTitle(notice), place: "macOS is set to deny it, so copies aren't saved",
                kind: "System Settings, Privacy & Security", primary: "Open Settings")
        case .needsAccessibility:
            TileView.Content(
                icon: icon, name: noticeTitle(notice), place: "Until it's allowed, ⏎ copies instead of pasting",
                kind: "System Settings, Privacy & Security, Accessibility", primary: "Open Settings")
        }
    }

    /// A clip's ⌘K action's name: "Paste", "Open in Safari"…
    func title(of action: ClipAction, for clip: Clip) -> String {
        action.title(canPaste: canPaste, linkApp: action == .openLink ? linkApps.app(for: clip.text)?.name : nil)
    }

    /// Runs a clip action (docs/BRIEF-CLIPBOARD.md §6). Pinning and deleting keep the panel open and go back to the
    /// list; everything else closes it first, so a paste lands in the app you were in. Delete waits for a second press
    /// on a pinned clip, or when a shortcut ran it (decision 74): a ⌘ letter is easy to press by habit.
    func perform(_ action: ClipAction, on clip: Clip, byShortcut: Bool = false) {
        switch action {
        case .pin, .unpin:
            keepSelection = (clip.id, backStack.last?.selection ?? tableView.selectedRow)
            if sublist != nil { goBack() }
            Task { await clipboard?.setPinned(action == .pin, for: clip.id) }
            return
        case .delete:
            if clip.pinned || byShortcut, !confirming {
                confirming = true
                refreshVisibleRows()
                return
            }
            keepSelection = (-1, backStack.last?.selection ?? tableView.selectedRow)
            if sublist != nil { goBack() }
            Task { await clipboard?.delete(clip.id) }
            return
        default:
            break
        }
        panel?.dismiss()
        switch action {
        case .paste: deliverClip(clip, .paste)
        case .copy:
            deliverClip(clip, .copy)
        case .pastePlainText: deliverClip(clip, canPaste ? .pastePlainText : .copyPlainText)
        case .openLink:
            if let url = URL(string: clip.text) { open(url, with: linkApps.app(for: clip.text)?.url) }
        case .reveal: reveal(clip)
        case .save: save(clip)
        case .pin, .unpin, .delete: break
        }
    }

    /// Paste next (`[hotkeys] paste_next`, decision 64), pressed at `time` (seconds since boot): pastes the next clip
    /// down the history, from the last one copied, into the app you're in, closing the panel if it's open. A pause or
    /// a new copy starts again from the newest; past the oldest, a press does nothing.
    func pasteNext(pressedAt time: TimeInterval) {
        guard let clipboard else { return }
        if pasteRun?.goesOn(copies: clipboard.copies, at: time) != true {
            pasteRun = PasteRun(clipboard.index.clips, copies: clipboard.copies, at: time)
        }
        guard let clip = pasteRun?.next(in: clipboard.index, at: time) else { return }
        panel?.dismiss()
        deliverClip(clip, .pasteNext)
    }

    /// Puts the clip back on the clipboard, and pastes it (`ClipPaster`).
    func deliver(_ clip: Clip, _ delivery: ClipDelivery) {
        guard let clipboard else { return }
        paster.deliver(clip, delivery, from: clipboard)
    }

    /// Shows the clip's files in Finder, or says they're gone.
    private func reveal(_ clip: Clip) {
        let urls = ClipText.paths(of: clip).map { URL(filePath: $0) }
        let read = fileFacts
        Task {
            let present = await runInBackground(qos: .userInitiated) { () -> [URL] in
                let present = urls.filter { read($0.path).exists }
                if !present.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(present) }
                return present
            }
            if present.isEmpty, let first = urls.first {
                failed(
                    "Couldn't reveal \(first.lastPathComponent)", nil,
                    reason: "It was moved or deleted since it was copied")
            }
        }
    }

    /// Saves a text or an image to `saveFolder` with a dated name, then says where (decision 39).
    private func save(_ clip: Clip) {
        guard let store = clipboard?.store else { return }
        let folder = saveFolder
        let date = now()
        Task {
            do throws(ClipboardStore.Failure) {
                let data: Data
                let fileExtension: String
                if clip.kind == .image {
                    let file = store.imageFile(of: clip.id)
                    guard let image = await runInBackground(qos: .userInitiated, { try? Data(contentsOf: file) }) else {
                        throw ClipboardStore.Failure(description: "the image is no longer in the history")
                    }
                    (data, fileExtension) = (image, "png")
                } else {
                    (data, fileExtension) = (Data(try await store.text(of: clip.id).utf8), "txt")
                }
                let saved = await runInBackground(qos: .userInitiated) { () -> Result<URL, ClipboardStore.Failure> in
                    let file = ClipFiles.destination(in: folder, at: date, extension: fileExtension)
                    do {
                        try data.write(to: file, options: .withoutOverwriting)
                        return .success(file)
                    } catch {
                        return .failure(ClipboardStore.Failure(description: error.localizedDescription))
                    }
                }
                reportSaved(try saved.get())
            } catch {
                if error.isGone { clipboard?.forget(clip.id) }
                failed("Couldn't save the clip", nil, reason: error.description)
            }
        }
    }
}
