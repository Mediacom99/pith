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

    /// Whether macOS itself uses `hotkey` (Spotlight's ⌘Space, ⌃Space for the input source, ⌘⇧4): Carbon registers
    /// it all the same, but the system's wins and Pith's never fires. Read from macOS's settings: a quick call.
    static func isSystemShortcut(_ hotkey: Shortcut) -> Bool {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr, let shortcuts = list?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        let code = Int(KeyLayout.keyCode(of: hotkey))
        let modifiers = Int(hotkey.modifiers)
        let mask = cmdKey | shiftKey | optionKey | controlKey
        return shortcuts.contains { shortcut in
            shortcut[kHISymbolicHotKeyEnabled] as? Bool == true && shortcut[kHISymbolicHotKeyCode] as? Int == code
                && (shortcut[kHISymbolicHotKeyModifiers] as? Int).map { $0 & mask == modifiers } == true
        }
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

/// The configured global hotkeys by name (`launcher`, `clipboard`, `paste_next`: `[hotkeys]`), registered with a
/// `HotKeyCenter`, and the problem for each one that couldn't be.
final class GlobalHotkeys {
    private let center: HotKeyCenter
    /// In the order they were first applied.
    private var names: [String] = []
    private var slots: [String: (current: (hotkey: Shortcut, id: HotKeyCenter.ID)?, problem: String?)] = [:]
    private var wanted: [String: (hotkey: Shortcut?, action: (TimeInterval) -> Void)] = [:]
    private var layoutObserver: NSObjectProtocol?
    /// Whether macOS itself uses a key. Tests swap it.
    private let isSystemShortcut: @MainActor (Shortcut) -> Bool
    /// Called after a layout change moved the hotkeys: what they show, and their problems, may have changed.
    var onLayoutChange: () -> Void = {}

    init(
        center: HotKeyCenter = HotKeyCenter(),
        isSystemShortcut: @escaping @MainActor (Shortcut) -> Bool = HotKeyCenter.isSystemShortcut
    ) {
        self.center = center
        self.isSystemShortcut = isSystemShortcut
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
    /// has none. All are let go first, so two whose keys trade places (a and q from U.S. to French) don't block each
    /// other.
    func layoutChanged() {
        let hotkeys = names.compactMap { name in
            wanted[name].flatMap { wanted in
                (current(name) ?? wanted.hotkey).map { (name: name, hotkey: $0, action: wanted.action) }
            }
        }
        for name in names {
            if let current = slots[name]?.current { center.unregister(current.id) }
        }
        for (name, hotkey, action) in hotkeys {
            if let id = center.register(hotkey, action: action) {
                slots[name] = ((hotkey, id), hotkey == wanted[name]?.hotkey ? nil : slots[name]?.problem)
            } else {
                slots[name] = (nil, "hotkeys.\(name) \"\(hotkey)\" is taken by another app")
            }
        }
        onLayoutChange()
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
            // A key macOS uses registers fine but never fires: it counts as taken, by macOS.
            let isSystems = isSystemShortcut(hotkey)
            if !isSystems, let id = center.register(hotkey, action: action) {
                slots[name] = ((hotkey, id), nil)
                continue
            }
            let kept = old.flatMap { old in center.register(old, action: action).map { (hotkey: old, id: $0) } }
            let fallback = kept.map { ", so it's still \"\($0.hotkey)\"" } ?? ""
            let holder = isSystems ? "macOS (System Settings, Keyboard, Keyboard Shortcuts)" : "another app"
            slots[name] = (kept, "hotkeys.\(name) \"\(hotkey)\" is taken by \(holder)\(fallback)")
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
