import Foundation

/// A TOML value of the kinds config.toml uses.
public enum TOMLValue: Sendable, Equatable {
    case string(String)
    case integer(Int)
    case float(Double)
    case boolean(Bool)
    case array([TOMLValue])
}

public struct TOMLError: Error, Sendable, Equatable, CustomStringConvertible {
    public let line: Int
    public let message: String
    public var description: String { "line \(line): \(message)" }
}

/// A small, strict TOML reader for what config.toml needs: comments, `[tables]` (dotted names), bare and quoted keys,
/// basic and literal strings, integers, floats, booleans and arrays (across lines too). Anything else (multi-line
/// strings, inline tables, dates, arrays of tables) is an error with its line number, never a guess.
struct TOMLReader {
    struct Entry: Sendable, Equatable {
        let value: TOMLValue
        let line: Int
    }

    /// Values by table name (`""` for the top level), then by key.
    static func parse(_ text: String) throws(TOMLError) -> [String: [String: Entry]] {
        var reader = TOMLReader(text: Array(text.unicodeScalars))
        return try reader.document()
    }

    private let text: [Unicode.Scalar]
    private var position = 0
    private var line = 1

    private init(text: [Unicode.Scalar]) {
        self.text = text
    }

    private var current: Unicode.Scalar? { position < text.count ? text[position] : nil }
    private var next: Unicode.Scalar? { position + 1 < text.count ? text[position + 1] : nil }

    private mutating func advance() {
        if current == "\n" { line += 1 }
        position += 1
    }

    private func error(_ message: String) -> TOMLError {
        TOMLError(line: line, message: message)
    }

    private mutating func document() throws(TOMLError) -> [String: [String: Entry]] {
        var tables: [String: [String: Entry]] = ["": [:]]
        var declared: Set<String> = []
        var table = ""
        while true {
            skipBlankLines()
            guard let character = current else { return tables }
            if character == "[" {
                advance()
                if current == "[" { throw error("arrays of tables ([[…]]) aren't supported") }
                skipSpaces()
                table = try key().joined(separator: ".")
                skipSpaces()
                try expect("]")
                guard declared.insert(table).inserted else { throw error("table [\(table)] is defined twice") }
                tables[table] = tables[table] ?? [:]
            } else {
                let entryLine = line
                var path = try key()
                let name = path.removeLast()
                let target = ([table] + path).filter { !$0.isEmpty }.joined(separator: ".")
                skipSpaces()
                try expect("=")
                skipSpaces()
                let value = try value()
                guard tables[target]?[name] == nil else { throw error("\(name) is set twice") }
                tables[target, default: [:]][name] = Entry(value: value, line: entryLine)
            }
            try endOfLine()
        }
    }

    /// A key, possibly dotted: `name`, `"quoted name"`, `a.b`.
    private mutating func key() throws(TOMLError) -> [String] {
        var parts: [String] = []
        repeat {
            skipSpaces()
            switch current {
            case "\"":
                parts.append(try basicString())
            case "'":
                parts.append(try literalString())
            default:
                var name = ""
                while let character = current, Self.isBareKeyCharacter(character) {
                    name.unicodeScalars.append(character)
                    advance()
                }
                guard !name.isEmpty else { throw error("expected a key") }
                parts.append(name)
            }
            skipSpaces()
        } while consume(".")
        return parts
    }

    private mutating func value() throws(TOMLError) -> TOMLValue {
        switch current {
        case "\"":
            if next == "\"", position + 2 < text.count, text[position + 2] == "\"" {
                throw error("multi-line strings aren't supported")
            }
            return .string(try basicString())
        case "'":
            if next == "'", position + 2 < text.count, text[position + 2] == "'" {
                throw error("multi-line strings aren't supported")
            }
            return .string(try literalString())
        case "[":
            return try array()
        case "{":
            throw error("inline tables aren't supported")
        case "t", "f":
            return try boolean()
        case let character?
        where character == "+" || character == "-" || character == "." || ("0"..."9").contains(character):
            return try number()
        default:
            throw error("expected a value")
        }
    }

    private mutating func basicString() throws(TOMLError) -> String {
        advance()  // the opening quote
        var string = ""
        while true {
            guard let character = current, character != "\n" else { throw error("unterminated string") }
            advance()
            switch character {
            case "\"":
                return string
            case "\\":
                string.unicodeScalars.append(try escape())
            default:
                string.unicodeScalars.append(character)
            }
        }
    }

    private mutating func escape() throws(TOMLError) -> Unicode.Scalar {
        guard let character = current else { throw error("unterminated string") }
        advance()
        switch character {
        case "\"": return "\""
        case "\\": return "\\"
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        case "u", "U":
            let digits = character == "u" ? 4 : 8
            var hex = ""
            for _ in 0..<digits {
                guard let digit = current, digit.properties.isASCIIHexDigit else {
                    throw error("bad \\\(character) escape")
                }
                hex.unicodeScalars.append(digit)
                advance()
            }
            guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else {
                throw error("bad \\\(character) escape")
            }
            return scalar
        default:
            throw error("unknown escape \\\(character)")
        }
    }

    private mutating func literalString() throws(TOMLError) -> String {
        advance()  // the opening quote
        var string = ""
        while true {
            guard let character = current, character != "\n" else { throw error("unterminated string") }
            advance()
            if character == "'" { return string }
            string.unicodeScalars.append(character)
        }
    }

    private mutating func array() throws(TOMLError) -> TOMLValue {
        advance()  // [
        var elements: [TOMLValue] = []
        while true {
            skipBlankLines()
            if consume("]") { return .array(elements) }
            elements.append(try value())
            skipBlankLines()
            if consume(",") { continue }
            try expect("]")
            return .array(elements)
        }
    }

    private mutating func boolean() throws(TOMLError) -> TOMLValue {
        let word = token()
        switch word {
        case "true": return .boolean(true)
        case "false": return .boolean(false)
        default: throw error("expected a value, found \(word)")
        }
    }

    private mutating func number() throws(TOMLError) -> TOMLValue {
        let word = token()
        let digits = word.replacingOccurrences(of: "_", with: "")
        if let integer = Int(digits) { return .integer(integer) }
        if digits.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }), let float = Double(digits) {
            return .float(float)
        }
        throw error("\(word) isn't a number this reader supports")
    }

    /// Characters up to the next delimiter: whitespace, `,`, `]` or `#`.
    private mutating func token() -> String {
        var word = ""
        while let character = current, ![" ", "\t", "\n", "\r", ",", "]", "#"].contains(character) {
            word.unicodeScalars.append(character)
            advance()
        }
        return word
    }

    private mutating func skipSpaces() {
        while current == " " || current == "\t" { advance() }
    }

    /// Spaces, newlines and comments.
    private mutating func skipBlankLines() {
        while let character = current {
            switch character {
            case " ", "\t", "\n", "\r": advance()
            case "#": skipComment()
            default: return
            }
        }
    }

    private mutating func skipComment() {
        while let character = current, character != "\n" { advance() }
    }

    /// After a statement only spaces and a comment may follow on the line.
    private mutating func endOfLine() throws(TOMLError) {
        skipSpaces()
        if current == "#" { skipComment() }
        if current == "\r" { advance() }
        guard current == nil || current == "\n" else { throw error("unexpected text after the value") }
    }

    private mutating func consume(_ character: Unicode.Scalar) -> Bool {
        guard current == character else { return false }
        advance()
        return true
    }

    private mutating func expect(_ character: Unicode.Scalar) throws(TOMLError) {
        guard consume(character) else { throw error("expected \(character)") }
    }

    private static func isBareKeyCharacter(_ character: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(character) || ("A"..."Z").contains(character) || ("0"..."9").contains(character)
            || character == "_" || character == "-"
    }
}
