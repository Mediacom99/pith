import AppKit
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
            KeyLayout.keyCode(of: hotkey),
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

/// The configured global hotkeys by name (`launcher`, `clipboard`: `[hotkeys]`, decision 55), registered with a
/// `HotKeyCenter`, and the problem for each one that couldn't be.
final class GlobalHotkeys {
    private let center: HotKeyCenter
    /// In the order they were first applied.
    private var names: [String] = []
    private var slots: [String: (current: (hotkey: Shortcut, id: HotKeyCenter.ID)?, problem: String?)] = [:]
    private var wanted: [String: (hotkey: Shortcut?, action: (TimeInterval) -> Void)] = [:]
    private var layoutObserver: NSObjectProtocol?

    init(center: HotKeyCenter = HotKeyCenter()) {
        self.center = center
        // A hotkey is registered on the key that types its letter in the layout in use (`KeyLayout`): switching
        // layouts moves it there.
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutChanged() }
        }
    }

    isolated deinit {
        if let layoutObserver { DistributedNotificationCenter.default().removeObserver(layoutObserver) }
    }

    /// Registers each hotkey again, on the keys of the layout now in use: the one it has, or the one configured if it
    /// has none.
    private func layoutChanged() {
        for name in names {
            guard let wanted = wanted[name], let hotkey = current(name) ?? wanted.hotkey else { continue }
            if let current = slots[name]?.current { center.unregister(current.id) }
            if let id = center.register(hotkey, action: wanted.action) {
                slots[name] = ((hotkey, id), hotkey == wanted.hotkey ? nil : slots[name]?.problem)
            } else {
                slots[name] = (nil, "hotkeys.\(name) \"\(hotkey)\" is taken by another app")
            }
        }
    }

    /// The key `name` is registered with, if any.
    func current(_ name: String) -> Shortcut? {
        slots[name]?.current?.hotkey
    }

    /// The hotkeys that couldn't be registered as configured.
    var problems: [String] {
        names.compactMap { slots[$0]?.problem }
    }

    /// Registers each hotkey as wanted. Those that changed are let go first, so two can swap keys or one can take
    /// another's. One that another app holds gets its old key back when it can, and its problem says so; nil lets go
    /// of it. One that didn't change keeps its key, and no longer has a problem.
    func apply(_ wanted: [(name: String, hotkey: Shortcut?, action: (TimeInterval) -> Void)]) {
        for (name, hotkey, action) in wanted {
            if !names.contains(name) { names.append(name) }
            self.wanted[name] = (hotkey, action)
        }
        let changed = wanted.filter { current($0.name) != $0.hotkey }
        for (name, _, _) in wanted where !changed.contains(where: { $0.name == name }) {
            slots[name]?.problem = nil
        }
        let old = changed.map { current($0.name) }
        for (name, _, _) in changed {
            if let current = slots[name]?.current { center.unregister(current.id) }
            slots[name] = (nil, nil)
        }
        for ((name, hotkey, action), old) in zip(changed, old) {
            guard let hotkey else { continue }
            if let id = center.register(hotkey, action: action) {
                slots[name] = ((hotkey, id), nil)
                continue
            }
            let kept = old.flatMap { old in center.register(old, action: action).map { (hotkey: old, id: $0) } }
            let fallback = kept.map { ", so it's still \"\($0.hotkey)\"" } ?? ""
            slots[name] = (kept, "hotkeys.\(name) \"\(hotkey)\" is taken by another app\(fallback)")
        }
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
