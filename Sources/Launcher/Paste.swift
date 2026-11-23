import AppKit
import ApplicationServices
import Carbon.HIToolbox
import LauncherCore

/// Puts a clip back on the clipboard, and pastes it into the app in front (`docs/MILESTONE-3.md` step 5). The panel
/// never activates Pith, so the app you were in is still in front when it closes: a ⌘V posted then lands in it.
/// Blocking (pasteboard IPC): call on a worker.
nonisolated enum Paster {
    /// Writes `items` as the clipboard's new contents, naming `source` as the app it came from (nspasteboard.org), so
    /// the history keeps that app when the recorder sees the copy. `transient` marks a copy the history must not
    /// record: plain text made from a rich clip, which is the clip itself.
    static func write(_ items: [[Representation]], source: String?, transient: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let objects = items.map { representations in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: .init(representation.type))
            }
            return item
        }
        if let first = objects.first {
            if let source { first.setString(source, forType: .init(ClipReading.sourceMarker)) }
            if transient { first.setData(Data(), forType: .init("org.nspasteboard.TransientType")) }
        }
        pasteboard.writeObjects(objects)
    }

    /// Presses ⌘V in the app in front. Needs Accessibility access; without it macOS drops the events.
    static func pressCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cgAnnotatedSessionEventTap)
        }
    }
}

/// Accessibility access, which posting ⌘V needs.
nonisolated enum Accessibility {
    /// Asks the system (a quick call, but IPC): call on a worker.
    static var isAllowed: Bool { AXIsProcessTrusted() }

    /// Shows macOS's own request, which leads to the setting.
    static func ask() {
        // The value of `kAXTrustedCheckOptionPrompt`, a global variable Swift 6 won't read from here.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static let settings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    static let clipboardSettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
}

/// What ⌘K offers on a clip (docs/BRIEF-CLIPBOARD.md §6), in the brief's order.
nonisolated enum ClipAction: CaseIterable, Sendable {
    case paste, copy, pastePlainText, openLink, reveal, save, pin, unpin, delete

    /// The actions for `clip`. Paste needs Accessibility access; without it the plain-text action copies.
    static func available(for clip: Clip, canPaste: Bool) -> [ClipAction] {
        var actions: [ClipAction] = canPaste ? [.paste, .copy] : [.copy]
        switch clip.kind {
        case .richText: actions += [.pastePlainText, .save]
        case .text: actions.append(.save)
        case .link: actions.append(.openLink)
        case .image: actions.append(.save)
        case .files: actions.append(.reveal)
        }
        return actions + [clip.pinned ? .unpin : .pin, .delete]
    }

    /// `linkApp`: the app that opens a link, once known ("Open in Safari").
    func title(canPaste: Bool, linkApp: String?) -> String {
        switch self {
        case .paste: "Paste"
        case .copy: "Copy to Clipboard"
        case .pastePlainText: canPaste ? "Paste as Plain Text" : "Copy as Plain Text"
        case .openLink: linkApp.map { "Open in \($0)" } ?? "Open Link"
        case .reveal: "Reveal in Finder"
        case .save: "Save as File"
        case .pin: "Pin"
        case .unpin: "Unpin"
        case .delete: "Delete"
        }
    }

    var symbol: String {
        switch self {
        case .paste: "arrow.down.doc"
        case .copy: "doc.on.doc"
        case .pastePlainText: "textformat"
        case .openLink: "arrow.up.forward.app"
        case .reveal: "folder"
        case .save: "square.and.arrow.down"
        case .pin: "pin"
        case .unpin: "pin.slash"
        case .delete: "trash"
        }
    }

    /// Deleting a pinned clip waits for a second ⏎, as Force Quit does (decision 28).
    static let deleteConfirmation = "Press ⏎ again to delete this pinned clip"
}

/// Where Save as File puts a clip (decision 39): "Clipboard 2026-11-23 at 14.05.png", then "… 2.png" and up when taken.
nonisolated enum ClipFiles {
    static func destination(in folder: URL, at date: Date, extension ext: String) -> URL {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd 'at' HH.mm"
        let name = "Clipboard \(format.string(from: date))"
        var candidate = folder.appending(path: "\(name).\(ext)")
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(name) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}
