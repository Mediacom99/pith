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

    /// Presses ⌘V in the app in front, with `key`, the key that types V in the layout in use (`KeyLayout`, looked up
    /// on the main thread). Needs Accessibility access; without it macOS drops the events.
    static func pressCommandV(key: UInt32) {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: isDown)
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

/// Puts clips back on the clipboard and presses ⌘V: for ⏎, the clip's ⌘K actions and paste next (decision 64). The
/// pasteboard and the key presses are IPC, so they run on a worker.
final class ClipPaster {
    /// Paste next checked Accessibility access at its press: whether it's given.
    var onAccessChecked: (_ allowed: Bool) -> Void = { _ in }
    /// A clip that couldn't be read back from the store: what failed, and why.
    var onFailure: (_ title: String, _ reason: String) -> Void = { _, _ in }
    /// The paste next in flight: the next one waits for it, so quick presses paste in order.
    private var pasting: Task<Void, Never>?

    /// Puts `clip` on the clipboard as `delivery` says, then presses ⌘V for a paste. Plain text is the clip itself,
    /// so it's marked for the history to skip, and the clip moves to the top as a copy would.
    func deliver(_ clip: Clip, _ delivery: ClipDelivery, from clipboard: ClipboardHistory) {
        let store = clipboard.store
        let vKey = KeyLayout.keyCode(typing: "v") ?? UInt32(kVK_ANSI_V)
        if delivery == .pasteNext { return pasteInTurn(clip, from: store, key: vKey) }
        Task {
            do throws(ClipboardStore.Failure) {
                if delivery.isPlainText {
                    let text = try await store.text(of: clip.id)
                    let plain = [
                        [Representation(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))]
                    ]
                    await runInBackground(qos: .userInitiated) {
                        Paster.write(plain, source: clip.source, transient: true)
                        if delivery.presses { Paster.pressCommandV(key: vKey) }
                    }
                    await clipboard.moveToTop(clip.id)
                } else {
                    let items = try await store.items(of: clip.id)
                    await runInBackground(qos: .userInitiated) {
                        Paster.write(items, source: clip.source, transient: false)
                        if delivery.presses { Paster.pressCommandV(key: vKey) }
                    }
                }
            } catch {
                onFailure(delivery.presses ? "Couldn't paste the clip" : "Couldn't copy the clip", error.description)
            }
        }
    }

    /// Paste next's paste (decision 64), after the one before it: its copy is marked for the history to skip, so the
    /// history keeps the order the run walks down. Accessibility is checked on the worker, at each press, since it can
    /// be given at any time. The next paste waits a moment, so the app has read the clipboard before it changes again.
    private func pasteInTurn(_ clip: Clip, from store: ClipboardStore, key vKey: UInt32) {
        let previous = pasting
        pasting = Task {
            await previous?.value
            do throws(ClipboardStore.Failure) {
                let items = try await store.items(of: clip.id)
                let pasted = await runInBackground(qos: .userInitiated) {
                    guard Accessibility.isAllowed else { return false }
                    Paster.write(items, source: clip.source, transient: true)
                    Paster.pressCommandV(key: vKey)
                    return true
                }
                onAccessChecked(pasted)
                try? await Task.sleep(for: .milliseconds(100))
            } catch {
                onFailure("Couldn't paste the clip", error.description)
            }
        }
    }
}
