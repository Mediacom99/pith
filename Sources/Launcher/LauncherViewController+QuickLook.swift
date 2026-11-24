import AppKit
import Quartz

// MARK: Quick Look

/// What the launcher asks of Quick Look's panel. `QLPreviewPanel` is the real one; tests give a fake, so nothing goes
/// on screen.
protocol PreviewPanel: AnyObject {
    var isVisible: Bool { get }
    /// Puts the preview one level above `window`, and asks the launcher, its controller, for the file.
    func show(above window: NSWindow)
    func reloadData()
    func orderOut(_ sender: Any?)
}

extension QLPreviewPanel: PreviewPanel {
    func show(above window: NSWindow) {
        level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        updateController()
        orderFront(nil)
        reloadData()
    }
}

extension LauncherViewController {
    /// The selected file or folder, which Quick Look previews (FEATURES.md §4.2), or the clipboard's image or first
    /// file.
    var previewURL: URL? {
        let row = tableView.selectedRow
        guard sublist == nil, rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case .item(let item):
            switch item.kind {
            case .file(let url), .folder(let url): return url
            case .app, .command: return nil
            }
        case .clip(let clip):
            switch clip.kind {
            case .image: return clipboard?.store.imageFile(of: clip.id)
            case .files: return ClipText.paths(of: clip).first.map { URL(filePath: $0) }
            case .text, .richText, .link: return nil
            }
        case .action, .problem, .notice, .clipAction:
            return nil
        }
    }

    private var quickLook: (any PreviewPanel)? { previewPanel(false) }

    var isPreviewing: Bool { quickLook?.isVisible == true }

    /// Shows or hides the preview of the selected file (⌘Y, or Space with an empty field: decision 20). The keyboard
    /// stays with the launcher, so ↑/↓ move through the results and the preview follows.
    func togglePreview() {
        if isPreviewing {
            closePreview()
            return
        }
        guard let url = previewURL, let preview = previewPanel(true), let window = view.window else { return }
        previewing = url
        (window as? LauncherPanel)?.previewWillShow()
        preview.show(above: window)
    }

    func closePreview() {
        quickLook?.orderOut(nil)
        previewing = nil
    }

    /// The selection moved: Quick Look follows it, keeps its file, or closes (`PreviewTarget`).
    func previewSelectionChanged(byUser: Bool) {
        let showing = isPreviewing ? previewing : nil
        switch PreviewTarget.change(showing: showing, selected: previewURL, byUser: byUser) {
        case .keep: break
        case .show(let url):
            previewing = url
            quickLook?.reloadData()
        case .close: closePreview()
        }
    }

    // Quick Look's controller hooks, declared nonisolated on NSObject; AppKit calls them on the main thread.

    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        true
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }
}

extension LauncherViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewing == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        previewing.map { $0 as NSURL }
    }

    /// Keys pressed while the preview has the keyboard (after a click on it). `preview` and `back` close it and give
    /// the keyboard back to the search; the panel's other keys do what they do there (↑/↓ move and the preview
    /// follows, ⏎ opens). Typing goes back to the search too. Nothing is left for Quick Look to act on by itself.
    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, let window = view.window else { return false }
        if isKey(.preview, event) || isKey(.back, event) {
            if !event.isARepeat { closePreview() }
            window.makeKey()
            return true
        }
        if handleKey(event) { return true }
        guard event.modifierFlags.intersection([.command, .control]).isEmpty, event.characters?.isEmpty == false
        else { return false }
        window.makeKey()
        window.sendEvent(event)
        return true
    }
}
