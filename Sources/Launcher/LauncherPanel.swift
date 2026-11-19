import AppKit

/// Panel geometry. Visual decisions, recorded in docs/ARCHITECTURE.md.
enum Layout {
    static let width: CGFloat = 680
    static let barHeight: CGFloat = 56
    static let rowHeight: CGFloat = 40
    static let visibleRows: CGFloat = 8
    static let resultsInset: CGFloat = 6
    static let iconSize: CGFloat = 28
    static let cornerRadius: CGFloat = 20
    static let expandedHeight = barHeight + 1 + visibleRows * rowHeight + 2 * resultsInset
}

/// The launcher window: built once at launch, then only shown and hidden.
///
/// Non-activating, so the app you were in stays frontmost while you type (FEATURES.md §2). It sits centered on the
/// screen under the mouse pointer and is only as tall as the search bar until there are results; the search bar
/// never moves.
final class LauncherPanel: NSPanel {
    let launcher = LauncherViewController()

    init() {
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func toggle() {
        isVisible ? dismiss() : present()
    }

    func present() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        // Center the expanded panel; the search bar is its top edge.
        let top = (area.midY + Layout.expandedHeight / 2).rounded()
        let height = frame.height
        setFrame(
            NSRect(x: (area.midX - Layout.width / 2).rounded(), y: top - height, width: Layout.width, height: height),
            display: false
        )
        makeKeyAndOrderFront(nil)
        launcher.focusSearchField()
    }

    /// Hides the panel and empties it for next time.
    func dismiss() {
        guard isVisible else { return }
        orderOut(nil)
        launcher.reset()
    }

    /// Clicking elsewhere, or opening an app, closes the launcher.
    override func resignKey() {
        super.resignKey()
        dismiss()
    }

    /// Grows to show results or shrinks back to the search bar, keeping the top edge in place.
    func setResultsVisible(_ visible: Bool) {
        let height = visible ? Layout.expandedHeight : Layout.barHeight
        guard frame.height != height else { return }
        setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: frame.width, height: height), display: true)
    }

    /// ⌃K and ⌃J move the selection like ↑ and ↓: send them down the same path.
    override func sendEvent(_ event: NSEvent) {
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
