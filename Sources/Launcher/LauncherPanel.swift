import AppKit

/// Panel geometry. Visual decisions, recorded in docs/ARCHITECTURE.md.
enum Layout {
    static let width: CGFloat = 680
    static let barHeight: CGFloat = 56
    static let rowHeight: CGFloat = 40
    static let visibleRows: CGFloat = 8
    static let resultsInset: CGFloat = 6
    static let iconSize: CGFloat = 28
    static let height = barHeight + 1 + visibleRows * rowHeight + 2 * resultsInset
}

/// The launcher window: built and drawn once at launch, then only moved, shown and hidden.
///
/// Non-activating, so the app you were in stays frontmost while you type (FEATURES.md §2). Opaque and fixed-size, so
/// the window server never blends, blurs or resizes it.
final class LauncherPanel: NSPanel {
    let launcher = LauncherViewController()

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
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
        setContentSize(NSSize(width: Layout.width, height: Layout.height))
        displayIfNeeded()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

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

    /// Centers the panel on the screen under the mouse pointer and gives it the keyboard, without activating the app.
    private func present(pressedAt: TimeInterval) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        setFrameOrigin(
            NSPoint(x: (area.midX - Layout.width / 2).rounded(), y: (area.midY - Layout.height / 2).rounded()))
        makeKeyAndOrderFront(nil)
        launcher.focusSearchField()
        displayIfNeeded()
        Log.latency("⌘P → panel drawn", since: pressedAt)
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
