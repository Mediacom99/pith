import Carbon.HIToolbox
import LauncherCore

/// System-wide hotkeys through Carbon's `RegisterEventHotKey`: no dependency and no Accessibility permission.
/// A registered key is taken from every app (⌘P no longer prints anywhere), as FEATURES.md §3 asks.
final class HotKeyCenter {
    typealias ID = UInt32

    private static let signature: OSType = 0x4C4E_4348  // "LNCH"

    private var actions: [ID: (_ pressedAt: TimeInterval) -> Void] = [:]
    private var hotKeys: [ID: EventHotKeyRef] = [:]
    private var nextID: ID = 1
    private var eventHandler: EventHandlerRef?

    /// Calls `action` on the main thread whenever `hotkey` is pressed, with the press time in seconds since boot (the
    /// clock of `NSEvent.timestamp`). Nil if the system refused the shortcut, for instance because another app holds
    /// it.
    func register(_ hotkey: Shortcut, action: @escaping (_ pressedAt: TimeInterval) -> Void) -> ID? {
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
            guard status == noErr else { return nil }
        }
        let id = nextID
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else { return nil }
        nextID += 1
        hotKeys[id] = hotKeyRef
        actions[id] = action
        return id
    }

    func unregister(_ id: ID) {
        if let hotKeyRef = hotKeys.removeValue(forKey: id) { UnregisterEventHotKey(hotKeyRef) }
        actions[id] = nil
    }

    fileprivate func fire(_ id: ID, pressedAt: TimeInterval) {
        actions[id]?(pressedAt)
    }

    isolated deinit {
        for hotKeyRef in hotKeys.values { UnregisterEventHotKey(hotKeyRef) }
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
