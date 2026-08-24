import AppKit
import CoreGraphics

/// Types text into whatever app currently has focus by briefly borrowing the
/// pasteboard and synthesising ⌘V. This is the only approach that works
/// reliably across native apps, Electron apps and browsers alike.
enum TextInserter {
    private static let virtualKeyV: CGKeyCode = 9
    /// Give the frontmost app time to read the pasteboard before we put the
    /// user's own clipboard back.
    private static let restoreDelay: TimeInterval = 0.4

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let snapshot = capture(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        sendPasteShortcut()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            restore(snapshot, to: pasteboard)
        }
    }

    private static func sendPasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        // Assigning rather than OR-ing drops any modifier the user happens to be
        // holding, which would otherwise turn ⌘V into ⌘⇧V or similar.
        down?.flags = .maskCommand
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func capture(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
    }

    private static func restore(_ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }

        let items: [NSPasteboardItem] = snapshot.map { contents in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
