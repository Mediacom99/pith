import AppKit

/// Panel geometry. Visual decisions, recorded in docs/ARCHITECTURE.md.
enum Layout {
    static let width: CGFloat = 680
    static let barHeight: CGFloat = 56
    static let rowHeight: CGFloat = 44
    static let visibleRows: CGFloat = 8
    static let resultsInset: CGFloat = 6
    static let iconSize: CGFloat = 28
    static let expandedHeight = barHeight + 1 + visibleRows * rowHeight + 2 * resultsInset
}

/// The launcher window: built and drawn once at launch, then only moved, shown and hidden.
///
/// Non-activating, so the app you were in stays frontmost while you type (FEATURES.md §2). Opaque, so the window server
/// never blends or blurs it. It's only the search bar until there are results, and resizes only when that changes.
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
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        hasShadow = true
        contentViewController = launcher
        setContentSize(NSSize(width: Layout.width, height: Layout.barHeight))
        displayIfNeeded()
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

    /// `pressedAt` is the hotkey's timestamp, in seconds since boot, for the latency log.
    func toggle(pressedAt: TimeInterval) {
        if isVisible {
            dismiss()
        } else {
            present(pressedAt: pressedAt)
        }
    }

    /// Puts the panel on the screen under the mouse pointer and gives it the keyboard, without activating the app.
    /// The expanded panel would be centered; the search bar is its top edge and stays there.
    private func present(pressedAt: TimeInterval) {
        let handled = ProcessInfo.processInfo.systemUptime
        launcher.prepareToShow()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let top = (area.midY + Layout.expandedHeight / 2).rounded()
        setFrameOrigin(NSPoint(x: (area.midX - Layout.width / 2).rounded(), y: top - frame.height))
        makeKeyAndOrderFront(nil)
        launcher.focusSearchField()
        let updated = ProcessInfo.processInfo.systemUptime
        displayIfNeeded()
        Log.latency("⌘P → panel drawn", event: pressedAt, handled: handled, updated: updated)
    }

    /// Hides the panel (and its Quick Look preview) and empties it for next time.
    func dismiss() {
        guard isVisible else { return }
        launcher.closePreview()
        orderOut(nil)
        launcher.reset()
    }

    /// Grows to show results, or shrinks back to the search bar, keeping the top edge in place.
    func setResultsVisible(_ visible: Bool) {
        let height = visible ? Layout.expandedHeight : Layout.barHeight
        guard frame.height != height else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: false)
    }

    /// Clicking elsewhere, or opening an app, closes the launcher; clicking into its Quick Look preview doesn't.
    override func resignKey() {
        super.resignKey()
        if launcher.isPreviewing { return }
        dismiss()
    }

    /// ⌃K and ⌃J move the selection like ↑ and ↓: send them down the same path. Space with an empty search field
    /// previews the selected file (decision 20).
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.characters == " ",
            event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
            launcher.searchField.stringValue.isEmpty, launcher.previewURL != nil,
            (firstResponder as? NSTextView)?.hasMarkedText() != true
        {
            launcher.togglePreview()
            return
        }
        if event.type == .keyDown,
            event.modifierFlags.intersection([.command, .option, .control, .shift]) == .control,
            let editor = firstResponder as? NSTextView, !editor.hasMarkedText()
        {
            switch event.charactersIgnoringModifiers {
            case "k":
                editor.doCommand(by: #selector(moveUp(_:)))
                return
            case "j":
                editor.doCommand(by: #selector(moveDown(_:)))
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    /// An agent app has no main menu, which is what normally delivers the editing shortcuts.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.charactersIgnoringModifiers == "k" {
            launcher.toggleActions()
            return true
        }
        if modifiers == .command, event.charactersIgnoringModifiers == "y" {
            launcher.togglePreview()
            return true
        }
        let action: Selector? =
            switch (modifiers, event.charactersIgnoringModifiers ?? "") {
            case (.command, "x"): #selector(NSText.cut(_:))
            case (.command, "c"): #selector(NSText.copy(_:))
            case (.command, "v"): #selector(NSText.paste(_:))
            case (.command, "a"): #selector(NSText.selectAll(_:))
            case (.command, "z"): Selector(("undo:"))
            case ([.command, .shift], "Z"): Selector(("redo:"))
            default: nil
            }
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
