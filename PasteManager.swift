import Cocoa

/// Incolla testo nella finestra attiva in primo piano sul Mac simulando Cmd+V.
/// Salva e ripristina la clipboard dell'utente.
enum PasteManager {

    static func paste(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Tutto su main thread: NSPasteboard è main-thread-only
        assert(Thread.isMainThread, "PasteManager.paste deve essere chiamato sul main thread")

        let pasteboard = NSPasteboard.general

        // 1. Salva il contenuto corrente della clipboard
        let savedContents = snapshotClipboard(pasteboard)

        // 2. Scrivi il testo da incollare
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Aspetta una frazione di secondo affinché la clipboard si aggiorni,
        //    poi simula ed invia il comando Cmd+V globalmente alla finestra attiva.
        //    Tempo ridotto a 0.05s per essere veloce ed affidabile.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulateCmdV()

            // 4. Ripristina la clipboard originale dopo 0.3 secondi.
            //    Questo lasso di tempo consente all'applicazione di leggere
            //    il testo prima che venga ripristinato il vecchio contenuto.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.restoreClipboard(pasteboard, contents: savedContents)
            }
        }
    }

    // MARK: - Privates

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

    /// Genera la simulazione di Cmd+V inviando l'evento nel flusso globale delle finestre attive.
    private static func simulateCmdV() {
        let source = CGEventSource(stateID: .privateState)
        let vKeyCode: CGKeyCode = 9 // 'v'

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags   = .maskCommand

        // Invia l'evento a livello globale all'applicazione attiva focalizzata (cghidEventTap)
        // Questo è il metodo ufficiale autorizzato dai permessi di Accessibilità.
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        Logger.log("PasteManager: Cmd+V inviato via cghidEventTap.")
    }
}
