import AppKit
import Carbon.HIToolbox
import LauncherCore

// MARK: Typing

extension LauncherViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        // `c ` in the launcher's field opens the clipboard (FEATURES.md §4), or the alias configured.
        if mode == .launcher, sublist == nil, !clipboardAlias.isEmpty,
            searchField.stringValue.lowercased() == clipboardAlias + " "
        {
            switchMode(to: .clipboard)
            return
        }
        let handled = ProcessInfo.processInfo.systemUptime
        // Typing cancels a second ⏎ that's waiting (decision 28), even when the rows stay the same.
        cancelConfirmation()
        refresh(keystroke: NSApp.currentEvent.map { ($0.timestamp, handled) })
    }

    /// The panel's keys are looked up before the field editor sees them (`handleKey`). A ⏎ or ⎋ that isn't one of
    /// them does nothing here, rather than end the field's editing, and nor do ⌥⏎, ⌥⇥ (which would type a line break
    /// or a tab into the query) and ⌥⎋ (word completion); other keys edit the field as usual.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        Self.swallowedCommands.contains(selector)
    }

    static let swallowedCommands: Set<Selector> = [
        #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.cancelOperation(_:)),
        #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
        #selector(NSResponder.insertTabIgnoringFieldEditor(_:)),
        #selector(NSResponder.complete(_:)),
    ]
}

// MARK: Keys

extension LauncherViewController {
    /// A key press, as `Shortcut.matches` compares it.
    struct KeyPress {
        var keyCode: UInt32
        var modifiers: UInt32
        var character: String?

        init(_ event: NSEvent) {
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            // The keypad's Enter (and fn+Return on a laptop) is Return.
            keyCode = event.keyCode == kVK_ANSI_KeypadEnter ? UInt32(kVK_Return) : UInt32(event.keyCode)
            modifiers =
                (flags.contains(.command) ? UInt32(cmdKey) : 0) | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
                | (flags.contains(.option) ? UInt32(optionKey) : 0)
                | (flags.contains(.control) ? UInt32(controlKey) : 0)
            // What the key types with ⌘ alone, so ⇧ and ⌥ don't change the letter, and a layout that turns QWERTY
            // under ⌘ still finds ⌘K.
            character =
                (event.characters(byApplyingModifiers: flags.intersection(.command))
                ?? event.charactersIgnoringModifiers)?.lowercased()
        }
    }

    /// The order keys are looked up in: `back` and `open` first, as they get their default back when a setting
    /// leaves them with none, even if another setting has it (decision 55).
    private static let lookupOrder: [PanelKey] = [.back, .open, .up, .down, .actions, .preview, .toLauncher]

    /// What a key press does in the panel (decision 55). True when it's taken: it did something, or it's one of the
    /// panel's keys that doesn't type. A key that types (a letter, Space, ⌫) acts only while the field is empty, and
    /// otherwise goes on to the field. In an actions list, `run_actions` comes first.
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        pressing = event
        defer { pressing = nil }
        let press = KeyPress(event)
        let isEmpty = searchField.stringValue.isEmpty
        func usable(_ shortcut: Shortcut?) -> Shortcut? {
            guard let shortcut,
                shortcut.matches(keyCode: press.keyCode, modifiers: press.modifiers, character: press.character),
                isEmpty || !shortcut.typesText
            else { return nil }
            return shortcut
        }
        // Held down, only up and down repeat: a held ⌫ mustn't run on into the launcher, Space flicker Quick Look, or ⏎
        // confirm what its first press asked about.
        let repeats = event.isARepeat
        if sublist != nil {
            for (position, shortcut) in keys.runActions.enumerated() where usable(shortcut) != nil {
                if repeats || runAction(at: position) { return true }
            }
        }
        for key in Self.lookupOrder {
            guard let shortcut = keys[key].lazy.compactMap(usable).first else { continue }
            if repeats, key != .up, key != .down { return true }
            return perform(key) || !shortcut.typesText
        }
        return false
    }

    /// Does what `key` does here; false when it doesn't apply now (nothing to preview, not in the clipboard).
    func perform(_ key: PanelKey) -> Bool {
        switch key {
        case .up: moveSelection(by: -1)
        case .down: moveSelection(by: 1)
        case .open where awaitingFiles && sublist == nil, .actions where awaitingFiles && sublist == nil:
            // The list is the previous query's until the files land: act on the query's list then.
            keyAfterSearch = key
        case .open: activate(row: tableView.selectedRow)
        case .actions: toggleActions()
        case .back:
            if isPreviewing {
                closePreview()
            } else if confirming {
                cancelConfirmation()
            } else if sublist != nil {
                goBack()
            } else {
                panel?.dismiss()
            }
        case .preview:
            guard isPreviewing || previewURL != nil else { return false }
            if let pressing, pressing === previewToggle { return true }
            previewToggle = pressing
            togglePreview()
        case .toLauncher:
            // From the clipboard's empty field back to the launcher.
            guard mode == .clipboard, sublist == nil, searchField.stringValue.isEmpty else { return false }
            switchMode(to: .launcher)
        case .runActions:
            return false
        }
        return true
    }

    /// Whether `event` is one of `key`'s shortcuts: Quick Look's window, when it has the keyboard, moves through the
    /// results with them.
    func isKey(_ key: PanelKey, _ event: NSEvent) -> Bool {
        let press = KeyPress(event)
        return keys[key].contains {
            $0.matches(keyCode: press.keyCode, modifiers: press.modifiers, character: press.character)
        }
    }
}
