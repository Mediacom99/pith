import AppKit

/// Panel geometry. Visual decisions, recorded in docs/ARCHITECTURE.md (decision 29).
enum Layout {
    static let width: CGFloat = 680
    static let barHeight: CGFloat = 52
    static let cornerRadius: CGFloat = 14
    /// The tile under the bar, which shows what ⏎ acts on: its height, its margin on every side, its corners and icon.
    static let tileHeight: CGFloat = 92
    static let tileMargin: CGFloat = 8
    static let tileRadius: CGFloat = 10
    static let tileIconSize: CGFloat = 48
    static let rowHeight: CGFloat = 32
    static let visibleRows: CGFloat = 8
    /// Under the last row.
    static let listBottomInset: CGFloat = 6
    /// Where the list starts: under the bar, its separator and the tile.
    static let listTop = barHeight + 1 + tileMargin * 2 + tileHeight
    static let expandedHeight = listTop + visibleRows * rowHeight + listBottomInset
    /// In the clipboard the tile is the preview: three rows taller, so five whole rows fit under it and the panel keeps
    /// its height (docs/BRIEF-CLIPBOARD.md).
    static let clipboardTileHeight = tileHeight + 3 * rowHeight
    static let clipboardListTop = listTop + 3 * rowHeight
    static let iconSize: CGFloat = 20
    /// The selection's distance from the panel's sides (the tile's margin, so the two line up), and its corners.
    static let selectionInset: CGFloat = tileMargin
    static let selectionRadius: CGFloat = 7
    /// One grid for the bar and the rows: icons start 10 pt inside the selection, and the magnifier is centered on
    /// the same column. Titles and the query start 10 pt after the icons and stop 10 pt inside the selection.
    static let iconX: CGFloat = selectionInset + 10
    static let textX: CGFloat = iconX + iconSize + 10
    static let textTrailing: CGFloat = selectionInset + 10
}

/// The launcher window: built and drawn once at launch, then only moved, shown and hidden.
///
/// Non-activating, so the app you were in stays frontmost while you type (FEATURES.md §2). The window is clear only so
/// its corners can be round: `PanelView` fills the rest, and nothing behind it is blurred. It's only the search bar
/// until there are results, and resizes only when that changes.
final class LauncherPanel: NSPanel {
    let launcher: LauncherViewController

    init(launcher: LauncherViewController) {
        self.launcher = launcher
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.barHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        contentViewController = launcher
        setContentSize(NSSize(width: Layout.width, height: Layout.barHeight))
        displayIfNeeded()
        // While Quick Look is up, another app coming to the front (⌘Tab, a click on its icon) closes both.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            MainActor.assumeIsolated {
                guard let self, self.launcher.isPreviewing else { return }
                self.dismiss()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// The search field's editor, with every text service that would run on each keystroke switched off: none of
    /// them belong in a search box.
    private let searchEditor: NSTextView = {
        let editor = NSTextView()
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.inlinePredictionType = .no
        editor.writingToolsBehavior = .none
        editor.mathExpressionCompletionType = .no
        editor.isAutomaticTextCompletionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.smartInsertDeleteEnabled = false
        return editor
    }()

    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        (object as? NSTextField) === launcher.searchField ? searchEditor : super.fieldEditor(createFlag, for: object)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// The launcher's hotkey (⌘P): opens the launcher, closes it, or switches to it from the clipboard. `pressedAt` is
    /// the hotkey's timestamp, in seconds since boot, for the latency log.
    func toggle(pressedAt: TimeInterval) {
        toggle(.launcher, pressedAt: pressedAt)
    }

    /// Opens the launcher if it isn't showing: for opening Pith.app again, the way in when the hotkey doesn't fire.
    func show() {
        guard !isVisible else { return }
        present(.launcher, pressedAt: ProcessInfo.processInfo.systemUptime)
    }

    /// The clipboard's hotkey (⌘⇧V, decision 34): the same, for the clipboard.
    func toggleClipboard(pressedAt: TimeInterval) {
        toggle(.clipboard, pressedAt: pressedAt)
    }

    private func toggle(_ mode: LauncherViewController.Mode, pressedAt: TimeInterval) {
        if !isVisible {
            present(mode, pressedAt: pressedAt)
        } else if launcher.mode == mode {
            dismiss()
        } else {
            launcher.switchMode(to: mode)
        }
    }

    /// Puts the panel on the screen under the mouse pointer and gives it the keyboard, without activating the app.
    /// The expanded panel would be centered; the search bar is its top edge and stays there.
    private func present(_ mode: LauncherViewController.Mode, pressedAt: TimeInterval) {
        let handled = ProcessInfo.processInfo.systemUptime
        launcher.prepareToShow(mode)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let top = (area.midY + Layout.expandedHeight / 2).rounded()
        setFrameOrigin(NSPoint(x: (area.midX - Layout.width / 2).rounded(), y: top - frame.height))
        makeKeyAndOrderFront(nil)
        launcher.focusSearchField()
        let updated = ProcessInfo.processInfo.systemUptime
        displayIfNeeded()
        Log.latency(
            mode == .clipboard ? "⌘⇧V → panel drawn" : "⌘P → panel drawn", event: pressedAt, handled: handled,
            updated: updated)
    }

    /// Hides the panel (and its Quick Look preview) and empties it for next time.
    /// Called after the panel closes, for work that mustn't hold up ⌘P: the daily update check.
    var onDismiss: () -> Void = {}

    func dismiss() {
        guard isVisible else { return }
        if let previewMonitor { NSEvent.removeMonitor(previewMonitor) }
        previewMonitor = nil
        launcher.closePreview()
        orderOut(nil)
        launcher.reset()
        onDismiss()
    }

    /// Grows to show results, or shrinks back to the search bar, keeping the top edge in place.
    func setResultsVisible(_ visible: Bool) {
        let height = visible ? Layout.expandedHeight : Layout.barHeight
        guard frame.height != height else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: false)
        // The shadow follows the window's shape, which just changed.
        invalidateShadow()
    }

    /// Clicking elsewhere, or opening an app, closes the launcher. With Quick Look up the preview can take the
    /// keyboard, so losing it says nothing then: `previewWillShow` watches for a click in another app instead.
    override func resignKey() {
        super.resignKey()
        if launcher.isPreviewing { return }
        dismiss()
    }

    /// Watches for a click in another app while Quick Look is up, which closes both; gone when the panel closes. A
    /// global monitor sees only other apps' events, so a click on the launcher or the preview doesn't count.
    private var previewMonitor: Any?

    func previewWillShow() {
        guard previewMonitor == nil else { return }
        previewMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown])
        {
            [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    /// The panel's keys (`[keys]`, decision 55) come before the field editor and the editing keys, unless an input
    /// method is composing text: it keeps its keys.
    func handleKey(_ event: NSEvent) -> Bool {
        if (firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
        return launcher.handleKey(event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey(event) { return }
        super.sendEvent(event)
    }

    /// An agent app has no main menu, which is what normally delivers the editing shortcuts. ⌘Q never quits Pith.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isKeyWindow, handleKey(event) { return true }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // What the key types with ⌘ alone, as the panel's keys are matched: a Russian or Greek layout still finds ⌘V.
        let character = (event.characters(byApplyingModifiers: .command) ?? event.charactersIgnoringModifiers ?? "")
            .lowercased()
        let action: Selector? =
            switch (modifiers, character) {
            case (.command, "x"): #selector(NSText.cut(_:))
            case (.command, "c"): #selector(NSText.copy(_:))
            case (.command, "v"): #selector(NSText.paste(_:))
            case (.command, "a"): #selector(NSText.selectAll(_:))
            case (.command, "z"): Selector(("undo:"))
            case ([.command, .shift], "z"): Selector(("redo:"))
            default: nil
            }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

/// The panel's background: the window color in a rounded rectangle with a hairline edge. The window around it is clear.
/// Flipped, so y grows downward and everything stays pinned to the top as the panel grows and shrinks.
///
/// Layer properties, not drawing: the compositor rounds and edges it, so growing and shrinking repaints nothing
/// (drawing the shape cost ~1 ms of CPU per resize).
final class PanelView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer.cornerRadius = Layout.cornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = Palette.edge.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
