import Carbon.HIToolbox
import Foundation

/// A global shortcut written like `cmd+p` or `ctrl+alt+space`: modifiers, then one key.
public struct Hotkey: Sendable, Equatable, CustomStringConvertible {
    /// The virtual key code (`kVK_…`): a physical key position on an ANSI keyboard.
    public let keyCode: UInt32
    /// Carbon modifier flags (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`).
    public let modifiers: UInt32
    /// The canonical spelling, like `cmd+shift+p`.
    public let description: String

    /// As macOS menus show it: `⇧⌘V`.
    public var symbols: String {
        let glyphs = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"]
        let parts = description.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        let key = parts.last ?? ""
        return parts.dropLast().compactMap { glyphs[$0] }.joined()
            + (key.count == 1 ? key.uppercased() : key.capitalized)
    }

    /// Nil unless `text` names known modifiers and exactly one known key. A global shortcut needs cmd, ctrl or alt
    /// (or a function key), so it never takes over plain typing.
    public init?(_ text: String) {
        var parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        // "cmd++" means the + key.
        if parts.count >= 2, parts.suffix(2) == ["", ""] {
            parts.removeLast(2)
            parts.append("+")
        }
        guard let keyName = parts.popLast(), let key = Self.keys[keyName] else { return nil }

        var modifiers: UInt32 = 0
        var names: [String] = []
        for (flag, name, aliases) in Self.modifierNames {
            if parts.contains(where: aliases.contains) {
                modifiers |= flag
                names.append(name)
            }
        }
        let known = Self.modifierNames.flatMap(\.aliases)
        guard parts.allSatisfy(known.contains) else { return nil }
        let isFunctionKey = keyName.first == "f" && keyName.count > 1
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 || isFunctionKey else { return nil }

        keyCode = key.code
        self.modifiers = modifiers
        description = (names + [key.name]).joined(separator: "+")
    }

    private static let modifierNames: [(flag: UInt32, name: String, aliases: [String])] = [
        (UInt32(controlKey), "ctrl", ["ctrl", "control", "⌃"]),
        (UInt32(optionKey), "alt", ["alt", "opt", "option", "⌥"]),
        (UInt32(shiftKey), "shift", ["shift", "⇧"]),
        (UInt32(cmdKey), "cmd", ["cmd", "command", "⌘"]),
    ]

    private static let keys: [String: (code: UInt32, name: String)] = {
        var keys: [String: (UInt32, String)] = [:]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C), ("d", kVK_ANSI_D), ("e", kVK_ANSI_E),
            ("f", kVK_ANSI_F), ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I), ("j", kVK_ANSI_J),
            ("k", kVK_ANSI_K), ("l", kVK_ANSI_L), ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R), ("s", kVK_ANSI_S), ("t", kVK_ANSI_T),
            ("u", kVK_ANSI_U), ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X), ("y", kVK_ANSI_Y),
            ("z", kVK_ANSI_Z), ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2), ("3", kVK_ANSI_3),
            ("4", kVK_ANSI_4), ("5", kVK_ANSI_5), ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
            ("9", kVK_ANSI_9), ("-", kVK_ANSI_Minus), ("=", kVK_ANSI_Equal), ("[", kVK_ANSI_LeftBracket),
            ("]", kVK_ANSI_RightBracket), ("\\", kVK_ANSI_Backslash), (";", kVK_ANSI_Semicolon),
            ("'", kVK_ANSI_Quote), (",", kVK_ANSI_Comma), (".", kVK_ANSI_Period), ("/", kVK_ANSI_Slash),
            ("`", kVK_ANSI_Grave),
        ]
        for (name, code) in letters { keys[name] = (UInt32(code), name) }
        let named: [([String], Int)] = [
            (["space"], kVK_Space), (["return", "enter"], kVK_Return), (["tab"], kVK_Tab),
            (["escape", "esc"], kVK_Escape), (["delete", "backspace"], kVK_Delete),
            (["left"], kVK_LeftArrow), (["right"], kVK_RightArrow), (["up"], kVK_UpArrow), (["down"], kVK_DownArrow),
            (["f1"], kVK_F1), (["f2"], kVK_F2), (["f3"], kVK_F3), (["f4"], kVK_F4), (["f5"], kVK_F5),
            (["f6"], kVK_F6), (["f7"], kVK_F7), (["f8"], kVK_F8), (["f9"], kVK_F9), (["f10"], kVK_F10),
            (["f11"], kVK_F11), (["f12"], kVK_F12), (["f13"], kVK_F13), (["f14"], kVK_F14), (["f15"], kVK_F15),
            (["f16"], kVK_F16), (["f17"], kVK_F17), (["f18"], kVK_F18), (["f19"], kVK_F19), (["f20"], kVK_F20),
        ]
        for (names, code) in named {
            for name in names { keys[name] = (UInt32(code), names[0]) }
        }
        keys["+"] = (UInt32(kVK_ANSI_Equal), "=")  // + is shift+= on ANSI keyboards
        return keys
    }()
}
