import Foundation

/// Text prepared once, at index time, so that matching it never allocates.
public struct SearchKey: Sendable {
    /// Lowercased, diacritic-folded UTF-8.
    let bytes: [UInt8]
    /// The bonus for matching each byte: word starts and camelCase humps score higher.
    let bonus: [UInt8]
    /// The set of bytes present (see `Folding.bit`), so most non-matches are rejected with one AND.
    let mask: UInt64

    public init(_ text: String) {
        var bytes: [UInt8] = []
        var bonus: [UInt8] = []
        Folding.fold(text, bytes: &bytes, bonus: &bonus)
        self.bytes = bytes
        self.bonus = bonus
        self.mask = Folding.mask(of: bytes)
    }
}

/// Turns text into lowercased, diacritic-folded UTF-8 plus a per-byte match bonus.
enum Folding {
    static func fold(_ text: String, bytes: inout [UInt8], bonus: inout [UInt8]) {
        bytes.reserveCapacity(text.utf8.count)
        bonus.reserveCapacity(text.utf8.count)
        var previous = CharClass.white

        // Most names are ASCII: fold them byte by byte, without creating any strings.
        if text.utf8.allSatisfy({ $0 < 0x80 }) {
            for byte in text.utf8 {
                let current = CharClass(ascii: byte)
                bytes.append(current == .upper ? byte | 0x20 : byte)
                bonus.append(Score.bonus(after: previous, at: current))
                previous = current
            }
            return
        }

        for character in text.folding(options: .diacriticInsensitive, locale: nil) {
            let current = CharClass(character)
            var isFirstByte = true
            for byte in character.lowercased().utf8 {
                bytes.append(byte)
                bonus.append(isFirstByte ? Score.bonus(after: previous, at: current) : 0)
                isFirstByte = false
            }
            previous = current
        }
    }

    static func mask(of bytes: [UInt8]) -> UInt64 {
        var mask: UInt64 = 0
        for byte in bytes { mask |= 1 << bit(byte) }
        return mask
    }

    /// a–z and 0–9 get a bit each; every other byte is hashed into the remaining 28.
    private static func bit(_ byte: UInt8) -> UInt64 {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"): UInt64(byte - UInt8(ascii: "a"))
        case UInt8(ascii: "0")...UInt8(ascii: "9"): UInt64(byte - UInt8(ascii: "0")) + 26
        default: UInt64(byte % 28) + 36
        }
    }
}

enum CharClass {
    case white, nonWord, delimiter, lower, upper, letter, number

    init(ascii byte: UInt8) {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"): self = .lower
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): self = .upper
        case UInt8(ascii: "0")...UInt8(ascii: "9"): self = .number
        case UInt8(ascii: " "), UInt8(ascii: "\t"): self = .white
        case UInt8(ascii: "/"), UInt8(ascii: ","), UInt8(ascii: ":"), UInt8(ascii: ";"), UInt8(ascii: "|"):
            self = .delimiter
        default: self = .nonWord
        }
    }

    init(_ character: Character) {
        if let ascii = character.asciiValue {
            self.init(ascii: ascii)
        } else if character.isWhitespace {
            self = .white
        } else if character.isUppercase {
            self = .upper
        } else if character.isLowercase {
            self = .lower
        } else if character.isLetter {
            self = .letter
        } else if character.isNumber {
            self = .number
        } else {
            self = .nonWord
        }
    }
}

/// fzf's scoring scheme (algo.go): a matched character is worth 16, a gap costs 3 plus 1 per extra character,
/// and matches at word starts, after delimiters or on camelCase humps earn a bonus.
enum Score {
    static let match: Int32 = 16
    static let gapStart: Int32 = -3
    static let gapExtension: Int32 = -1
    /// Every character in a run of consecutive matches earns at least this.
    static let consecutive: Int32 = 4
    /// The first query character's bonus counts double.
    static let firstCharMultiplier: Int32 = 2

    /// At the start of the text or after whitespace.
    static let boundaryWhite: UInt8 = 10
    /// After `/ , : ; |`.
    static let boundaryDelimiter: UInt8 = 9
    /// After any other non-word character, such as `-`, `_` or `.`.
    static let boundary: UInt8 = 8
    /// Matching a non-word character itself.
    static let nonWord: UInt8 = 8
    /// A lowercase-to-uppercase hump, or the first digit after a non-digit.
    static let camel: UInt8 = 7

    static func bonus(after previous: CharClass, at current: CharClass) -> UInt8 {
        switch current {
        case .white: return boundaryWhite
        case .nonWord, .delimiter: return nonWord
        case .lower, .upper, .letter, .number: break
        }
        switch previous {
        case .white: return boundaryWhite
        case .delimiter: return boundaryDelimiter
        case .nonWord: return boundary
        case .lower where current == .upper: return camel
        default: return current == .number && previous != .number ? camel : 0
        }
    }
}
