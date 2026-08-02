import Cocoa

/// Pastes text into whatever app currently has focus by simulating Cmd+V.
///
/// The user's clipboard is snapshotted before the paste and restored afterwards,
/// so dictating never destroys what they had copied.
enum PasteManager {

    /// Delay before sending Cmd+V, giving the pasteboard time to settle.
    private static let pasteDelay: TimeInterval = 0.05

    /// Delay before restoring the original clipboard. Long enough for the target
    /// app to have read the pasted text, short enough not to be noticeable.
    private static let restoreDelay: TimeInterval = 0.3

    static func paste(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // NSPasteboard is main-thread only.
        assert(Thread.isMainThread, "PasteManager.paste must be called on the main thread")

        let pasteboard = NSPasteboard.general

        // 1. Save whatever the user currently has on the clipboard.
        let savedContents = snapshotClipboard(pasteboard)

        // 2. Put our text there instead.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Send Cmd+V to the focused app.
        DispatchQueue.main.asyncAfter(deadline: .now() + pasteDelay) {
            simulateCmdV()

            // 4. Put the user's clipboard back.
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                restoreClipboard(pasteboard, contents: savedContents)
            }
        }
    }

    // MARK: - Private

    private static func snapshotClipboard(_ pasteboard: NSPasteboard) -> [(NSPasteboard.PasteboardType, Data)] {
        var snapshot: [(NSPasteboard.PasteboardType, Data)] = []
        guard let types = pasteboard.types else { return snapshot }
        for type in types {
            if let data = pasteboard.data(forType: type) {
                snapshot.append((type, data))
            }
        }
        return snapshot
    }

    private static func restoreClipboard(_ pasteboard: NSPasteboard, contents: [(NSPasteboard.PasteboardType, Data)]) {
        pasteboard.clearContents()
        guard !contents.isEmpty else { return }
        for (type, data) in contents {
            pasteboard.setData(data, forType: type)
        }
    }

    /// Synthesises Cmd+V and posts it to the focused application.
    ///
    /// Posting to `.cghidEventTap` is the sanctioned route for this and is what
    /// the Accessibility permission grants.
    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .privateState)
        let vKeyCode: CGKeyCode = 9 // 'v'

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        Logger.log("PasteManager: Cmd+V posted via cghidEventTap.")
    }
}
