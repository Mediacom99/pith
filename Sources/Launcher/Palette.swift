import AppKit

/// The few colors the system doesn't have, each in light and dark (decision 29): quiet fills instead of the accent,
/// and color only where it means something. Everything else uses the semantic system colors.
nonisolated enum Palette {
    /// Folders, kinds, the second key's words, key caps and symbols: a gray between the secondary and tertiary label
    /// colors, opaque (text fields drew the translucent version darker). On the selection, its darkest background,
    /// 4.9:1 light and 4.7:1 dark.
    static let quiet = dynamic(
        light: NSColor(srgbRed: 0.4, green: 0.4, blue: 0.4, alpha: 1),
        dark: NSColor(srgbRed: 0.631, green: 0.631, blue: 0.631, alpha: 1))
    /// The tile's fill.
    static let tile = dynamic(light: NSColor(white: 0, alpha: 0.035), dark: NSColor(white: 1, alpha: 0.045))
    /// The selected row's fill, and the key caps'. Too faint to mark the selection alone (1.2:1 light, 1.4:1 dark),
    /// so the selected row also ends in ↩.
    static let selection = dynamic(light: NSColor(white: 0, alpha: 0.07), dark: NSColor(white: 1, alpha: 0.1))
    /// Force Quit waiting for its second ⏎: its text and symbol (4.7:1 light, 4.9:1 dark on `dangerFill`).
    static let danger = dynamic(
        light: NSColor(srgbRed: 0.843, green: 0, blue: 0.082, alpha: 1),
        dark: NSColor(srgbRed: 1, green: 0.412, blue: 0.38, alpha: 1))
    /// Its row's fill: the system red, faint.
    static let dangerFill = dynamic(
        light: NSColor(srgbRed: 1, green: 0.231, blue: 0.188, alpha: 0.1),
        dark: NSColor(srgbRed: 1, green: 0.271, blue: 0.227, alpha: 0.16))
    /// A config problem's symbol. Darker than the system orange in light mode, which is 2.2:1 on white.
    static let warning = dynamic(
        light: NSColor(srgbRed: 0.788, green: 0.204, blue: 0, alpha: 1),
        dark: NSColor(srgbRed: 1, green: 0.624, blue: 0.039, alpha: 1))
    /// The panel's edge, which keeps it apart from a window of the same color behind it.
    static let edge = dynamic(light: NSColor(white: 0, alpha: 0.12), dark: NSColor(white: 1, alpha: 0.14))

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
}
