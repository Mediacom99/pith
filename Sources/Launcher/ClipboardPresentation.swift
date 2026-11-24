import Foundation
import LauncherCore

/// Something the clipboard says above its clips, until it's dealt with.
enum ClipboardNotice: Equatable {
    /// Recording was paused from the launcher; ⏎ resumes it.
    case paused
    /// macOS is set to deny Pith the clipboard, so nothing is recorded; ⏎ opens the setting.
    case cannotRead
    /// Pasting needs Accessibility access: until then ⏎ copies, and ⏎ on the notice opens the setting.
    case needsAccessibility
}

/// How a clip goes back: with everything it was copied with, or as plain text; pasted into the app in front, or only
/// put on the clipboard.
nonisolated enum ClipDelivery: Sendable {
    /// `pasteNext` is paste next's (decision 64): a paste the history doesn't record, in turn with the one before.
    case paste, copy, pastePlainText, copyPlainText, pasteNext

    var presses: Bool { self == .paste || self == .pastePlainText || self == .pasteNext }
    var isPlainText: Bool { self == .pastePlainText || self == .copyPlainText }
}

/// The words a clip shows in its row and on the tile (`docs/BRIEF-CLIPBOARD.md` §5). Pure functions of the clip, the
/// query and the time, so tests and snapshots can pin them.
enum ClipText {
    /// The most of a text the tile lays out: its first lines, never the whole of a long one.
    static let previewLines = 8
    static let previewCharacters = 1_200
    /// A text this long (in bytes) has its size on the tile.
    static let longText = 10_000

    /// The row's title: a text's first line that isn't blank (while searching, the first that matches), whitespace
    /// collapsed; a link's URL without its scheme; "Image"; the first file's name, and how many more. Text that is only
    /// whitespace is described, in the quiet color.
    static func title(of clip: Clip, query: String = "") -> (text: String, isQuiet: Bool) {
        switch clip.kind {
        case .text, .richText:
            let line =
                ClipboardIndex.matchingLine(in: clip.text, for: query)
                ?? clip.text.split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) }
            guard let line else { return ("Spaces and line breaks", true) }
            return (line.split(whereSeparator: \.isWhitespace).joined(separator: " "), false)
        case .link:
            return (withoutScheme(clip.text), false)
        case .image:
            return ("Image", false)
        case .files:
            // The count from the whole list: a long one is cut in memory.
            let name = (paths(of: clip).first.map { ($0 as NSString).lastPathComponent }) ?? ""
            return (clip.lines > 1 ? "\(name) and \((clip.lines - 1).formatted()) more" : name, false)
        }
    }

    /// After the title: how many lines a text has, an image's size, the files' folder.
    static func detail(of clip: Clip) -> String {
        switch clip.kind {
        case .text, .richText: clip.lines > 1 ? "\(clip.lines.formatted()) lines" : ""
        case .link: ""
        case .image: "\(clip.pixelWidth) × \(clip.pixelHeight)"
        case .files: folders(of: clip)
        }
    }

    /// The files' folder from the home folder as `~`, or how many folders they're in.
    static func folders(of clip: Clip) -> String {
        let folders = Set(paths(of: clip).map { ($0 as NSString).deletingLastPathComponent })
        guard folders.count == 1, let folder = folders.first else { return "\(folders.count) folders" }
        return (folder as NSString).abbreviatingWithTildeInPath
    }

    /// The files' paths in memory: all of them, or the first 2,500 or so of a longer list, without one cut short.
    static func paths(of clip: Clip) -> [String] {
        var paths = clip.text.split(separator: "\n").map(String.init)
        if clip.text.utf8.count < clip.textBytes, !paths.isEmpty { paths.removeLast() }
        return paths
    }

    /// What the tile previews of a text: its first lines, as they'll paste, and one more when there is one, so the
    /// preview's last line ends in "…".
    static func preview(of clip: Clip) -> String {
        var lines = 0
        var end = clip.text.endIndex
        for index in clip.text.indices where clip.text[index].isNewline {
            lines += 1
            if lines == previewLines + 1 {
                end = index
                break
            }
        }
        return String(clip.text[..<end].prefix(previewCharacters)).trimmingCharacters(in: .newlines)
    }

    /// When a clip was copied, at the end of its row: "now", "5 min", "14:05", "yesterday", "Mon", "Nov 12".
    static func age(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return timeFormat.string(from: date) }
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? .max
        if days == 1 { return "yesterday" }
        if (2..<7).contains(days) { return shortWeekdayFormat.string(from: date) }
        return dayFormat.string(from: date)
    }

    /// On the tile: "copied today at 14:05", "copied yesterday", "copied Tuesday", "copied Nov 12".
    static func copied(_ date: Date, now: Date) -> String {
        LauncherViewController.opened(date, now: now).replacingOccurrences(of: "opened", with: "copied")
    }

    /// The tile's line about a clip: its kind, then what's known about it, then when and where it was copied:
    /// "Text · 12 lines · copied today at 14:05 from Terminal".
    static func about(_ parts: [String], copied date: Date, from source: String?, now: Date) -> String {
        let when = copied(date, now: now) + (source.map { " from \($0)" } ?? "")
        return (parts.filter { !$0.isEmpty } + [when]).joined(separator: " · ")
    }

    static func kindName(_ kind: Clip.Kind) -> String {
        switch kind {
        case .text: "Text"
        case .richText: "Rich text"
        case .link: "Link"
        case .image: "Image"
        case .files: "Files"
        }
    }

    /// "2.1 MB", as Finder counts.
    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    /// A link's host, the tile's name for it: "github.com".
    static func host(of clip: Clip) -> String {
        URL(string: clip.text)?.host() ?? withoutScheme(clip.text)
    }

    /// `https://github.com/acme` → `github.com/acme`; `mailto:hello@acme.example` → `hello@acme.example`.
    static func withoutScheme(_ link: String) -> String {
        for scheme in ["https://", "http://", "mailto:"] where link.lowercased().hasPrefix(scheme) {
            return String(link.dropFirst(scheme.count))
        }
        return link
    }

    /// An image's preview size in points: fitted into the tile's box, never past its own pixels (at 2x).
    static func previewSize(of clip: Clip) -> CGSize {
        let box = ClipboardStore.previewPixels
        guard clip.pixelWidth > 0, clip.pixelHeight > 0 else { return .zero }
        let fit = min(1, Double(box.width) / Double(clip.pixelWidth), Double(box.height) / Double(clip.pixelHeight))
        return CGSize(
            width: max(1, (Double(clip.pixelWidth) * fit / 2).rounded()),
            height: max(1, (Double(clip.pixelHeight) * fit / 2).rounded()))
    }

    private static let timeFormat: DateFormatter = {
        let format = DateFormatter()
        format.timeStyle = .short
        format.dateStyle = .none
        return format
    }()

    private static func englishFormat(_ template: String) -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en")
        format.setLocalizedDateFormatFromTemplate(template)
        return format
    }
    private static let shortWeekdayFormat = englishFormat("EEE")
    private static let dayFormat = englishFormat("MMMd")
}
