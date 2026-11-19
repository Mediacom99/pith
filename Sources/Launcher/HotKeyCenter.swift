import Carbon.HIToolbox

/// System-wide hotkeys through Carbon's `RegisterEventHotKey`: no dependency and no Accessibility permission.
/// A registered key is taken from every app (⌘P no longer prints anywhere), as FEATURES.md §3 asks.
final class HotKeyCenter {
    struct Shortcut {
        /// A virtual key code, such as `kVK_ANSI_P`.
        var keyCode: UInt32
        /// Carbon modifier flags, such as `cmdKey | shiftKey`.
        var modifiers: UInt32
    }

    private static let signature: OSType = 0x4C4E_4348  // "LNCH"

    private var actions: [UInt32: (_ pressedAt: TimeInterval) -> Void] = [:]
    private var hotKeys: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?

    /// Calls `action` on the main thread whenever `shortcut` is pressed, with the press time in seconds since boot
    /// (the clock of `NSEvent.timestamp`). False if the system refused the shortcut.
    func register(_ shortcut: Shortcut, action: @escaping (_ pressedAt: TimeInterval) -> Void) -> Bool {
        if eventHandler == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(
                GetEventDispatcherTarget(),
                hotKeyPressed,
                1,
                &pressed,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
            guard status == noErr else { return false }
        }
        let id = UInt32(actions.count + 1)
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &hotKey
        )
        guard status == noErr, let hotKey else { return false }
        hotKeys.append(hotKey)
        actions[id] = action
        return true
    }

    fileprivate func fire(_ id: UInt32, pressedAt: TimeInterval) {
        actions[id]?(pressedAt)
    }

    isolated deinit {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

/// Carbon delivers hotkey events on the main thread.
private nonisolated func hotKeyPressed(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ center: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let center else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr else { return status }
    let pressedAt = GetEventTime(event)
    let hotKeys = Unmanaged<HotKeyCenter>.fromOpaque(center).takeUnretainedValue()
    MainActor.assumeIsolated { hotKeys.fire(id.id, pressedAt: pressedAt) }
    return noErr
}
