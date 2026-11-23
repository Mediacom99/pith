import Carbon.HIToolbox
import LauncherCore

/// The key that types a character in the keyboard layout in use (Dvorak, Colemak, AZERTY…), for keys named by their
/// letter: the global hotkeys and the paste's ⌘V. As menus do, it's the character typed with ⌘ held, so a layout that
/// switches to QWERTY under ⌘ keeps QWERTY's keys. A layout with no letters (Russian, Greek) falls back to the last
/// one that has them. The Text Input Sources API wants the main thread; a lookup is at most 128 translations.
enum KeyLayout {
    /// The key code that types `character`, or nil when no key in the layout does.
    static func keyCode(typing character: String) -> UInt32? {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource(),
        ]
        for case let source? in sources.map({ $0?.takeRetainedValue() }) {
            guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { continue }
            let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
            let code = data.withUnsafeBytes { bytes -> UInt32? in
                guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                return (0..<128).first { code in
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        layout, UInt16(code), UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8) & 0xFF,
                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count,
                        &length, &characters)
                    return status == noErr && length > 0
                        && String(utf16CodeUnits: characters, count: length).lowercased() == character
                }.map(UInt32.init)
            }
            if let code { return code }
        }
        return nil
    }

    /// The key code a shortcut is pressed with in the layout in use: a letter, digit or mark where the layout puts it,
    /// other keys (arrows, F keys, Space) where they always are.
    static func keyCode(of shortcut: Shortcut) -> UInt32 {
        guard shortcut.isCharacter else { return shortcut.keyCode }
        return keyCode(typing: shortcut.key) ?? shortcut.keyCode
    }
}
