import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Core Objects (non-UI)
    private let appState = AppState()
    private var keyboardManager: KeyboardManager!
    private let speechManager = SpeechManager()
    private var ollamaManager: OllamaManager!

    // MARK: - Windows
    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow!
    private var dashboardWindow: NSWindow!

    // MARK: - Nuovi Stati Interazione (Click-to-Toggle / Hold-to-Talk)
    private var lastKeyDownTime: Date?
    private var keyUpTimer: Timer?
    private var isLockedListening = false
    private var mouseMonitorLocal: Any?
    private var mouseMonitorGlobal: Any?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupMenuBar()

        // Inizializza i manager con i valori dall'AppState
        keyboardManager = KeyboardManager(keyCode: appState.hotkeyKeyCode)
        ollamaManager = OllamaManager(modelName: appState.ollamaModelName)

        // Prepara finestre
        setupOverlayWindow()
        setupDashboardWindow()

        // Collega tutti i callback
        setupCallbacks()

        // Richiedi permessi e mostra dashboard se mancanti
        speechManager.requestPermissions { [weak self] speech, mic in
            guard let self else { return }
            self.appState.hasSpeechPermission = speech
            self.appState.hasMicrophonePermission = mic

            if !speech || !mic || !AXIsProcessTrusted() {
                self.showDashboard()
            }
        }

        // Avvia il keyboard manager
        keyboardManager.start()

        // Verifica stato Ollama all'avvio
        refreshOllamaStatus()

        // Osserva richiesta di registrazione hotkey dalla Dashboard
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStartHotkeyRecording),
            name: NSNotification.Name("mywispr.startHotkeyRecording"),
            object: nil
        )

        // Osserva richiesta di toggle della Dashboard
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleDashboard),
            name: NSNotification.Name("mywispr.toggleDashboard"),
            object: nil
        )

        // Osserva richiesta di refresh di Ollama dalla Dashboard
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRefreshOllamaNotification),
            name: NSNotification.Name("mywispr.refreshOllama"),
            object: nil
        )

        // Mostra la notch in sovrimpressione permanente
        overlayWindow.showCentered()
        
        setupMouseMonitors()
        
        Logger.log("MyWispr avviato. AXIsProcessTrusted: \(AXIsProcessTrusted())")
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardManager.stop()
        if let monitor = mouseMonitorLocal {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = mouseMonitorGlobal {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (richiesto da macOS per Cmd+Q e altre shortcut)
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MyWispr")
        let quitItem = NSMenuItem(title: "Esci da MyWispr", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu (abilita Cmd+C/V/X/A nei text field della Dashboard)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Taglia",          action: #selector(NSText.cut(_:)),       keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copia",           action: #selector(NSText.copy(_:)),      keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Incolla",         action: #selector(NSText.paste(_:)),     keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Seleziona Tutto", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "MyWispr")
        }
        let menu = NSMenu()
        
        let openItem = NSMenuItem(title: "Apri Dashboard", action: #selector(showDashboard), keyEquivalent: "d")
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Esci", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }

    private func setupOverlayWindow() {
        overlayWindow = OverlayWindow(appState: appState)
        let overlayView = OverlayView().environmentObject(appState)
        
        let hostingView = PassThroughHostingView(rootView: overlayView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.overlayWindow = overlayWindow
        
        overlayWindow.contentView = hostingView
    }

    private func setupDashboardWindow() {
        dashboardWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        dashboardWindow.title = "MyWispr"
        dashboardWindow.isReleasedWhenClosed = false
        let dashView = DashboardView().environmentObject(appState)
        dashboardWindow.contentView = NSHostingView(rootView: dashView)
        dashboardWindow.center()
    }

    private func setupCallbacks() {
        // ---------------------------------------------------------------
        // LOGICA DOPPIO CLICK (Double-Press to Lock)
        //
        // Stato A - HOLD-TO-TALK:
        //   Premi e tieni → avvia registrazione immediata
        //   Rilasci → ferma registrazione e processa
        //
        // Stato B - LOCK-TO-LISTEN (mani libere):
        //   Due pressioni rapide (< 0.35s) → entra in modalità ascolto
        //   continuo. La seconda pressione NON avvia una nuova registrazione
        //   (quella già attiva viene mantenuta).
        //   Per uscire: premi di nuovo l'hotkey, O click sinistro del mouse.
        // ---------------------------------------------------------------

        keyboardManager.onKeyDown = { [weak self] in
            guard let self else { return }
            guard self.appState.hasSpeechPermission && self.appState.hasMicrophonePermission else {
                Logger.log("onKeyDown ignorato: permessi mancanti.")
                self.showDashboard()
                return
            }

            // ── Se siamo già in Lock-to-Listen: questo keyDown esce dalla modalità ──
            if self.isLockedListening {
                Logger.log("Hotkey GIU mentre in ascolto bloccato → uscita da Lock.")
                self.isLockedListening = false
                self.appState.isRecording = false
                self.speechManager.stopRecording()
                return
            }

            // ── Rilevamento doppio click ──
            let now = Date()
            let timeSinceLast = self.lastKeyDownTime.map { now.timeIntervalSince($0) } ?? Double.infinity
            self.lastKeyDownTime = now

            if timeSinceLast < 0.35 {
                // ── DOPPIO CLICK: entra in Lock-to-Listen ──
                // Annulla il keyUpTimer del primo press così non stoppiamo la registrazione
                self.keyUpTimer?.invalidate()
                self.keyUpTimer = nil
                Logger.log("DOPPIO CLICK rilevato (\(String(format: "%.2f", timeSinceLast))s) → Lock-to-Listen attivo.")
                self.isLockedListening = true
                // La registrazione avviata dal primo keyDown continua normalmente.
                // Non avviamo una seconda sessione.
            } else {
                // ── PRIMO CLICK: Hold-to-Talk classico ──
                // Assicuriamoci che non ci sia una sessione attiva rimasta sporca
                if self.appState.isRecording {
                    Logger.log("WARN: isRecording era true all'avvio di un nuovo hold-to-talk. Cancello la sessione precedente.")
                    self.speechManager.cancelRecording()
                    self.appState.isRecording = false
                    self.appState.isProcessing = false
                    self.appState.partialTranscript = ""
                    self.appState.audioLevel = 0
                }
                Logger.log("Hotkey GIU (hold-to-talk).")
                self.appState.partialTranscript = ""
                self.appState.audioLevel = 0
                self.appState.isRecording = true
                self.appState.overlayMode = .recording
                self.speechManager.startRecording()
            }
        }

        keyboardManager.onKeyUp = { [weak self] in
            guard let self else { return }

            // Se siamo in Lock-to-Listen, il keyUp non fa nulla
            if self.isLockedListening {
                Logger.log("Hotkey SU ignorato (Lock-to-Listen attivo).")
                return
            }

            // Salva il momento del rilascio per misurare la durata della pressione
            let keyUpTime = Date()

            // Finestra doppio click: aspetta 0.32s prima di confermare il singolo press.
            // Se arriva un secondo keyDown entro 0.32s, il timer viene invalidato
            // e non facciamo lo stop.
            self.keyUpTimer?.invalidate()
            self.keyUpTimer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: false) { [weak self] _ in
                guard let self, !self.isLockedListening else { return }

                // Se nel frattempo non stiamo più registrando (es. onSilence già scattato),
                // non fare nulla per evitare doppia finalizzazione.
                guard self.appState.isRecording else {
                    Logger.log("keyUpTimer: non in registrazione, ignoro.")
                    return
                }

                // Misura quanto a lungo il tasto è stato tenuto premuto
                let holdDuration = self.lastKeyDownTime.map { keyUpTime.timeIntervalSince($0) } ?? 1.0

                // Click brevissimo (<0.25s) senza trascrizione parziale → accidentale
                if holdDuration < 0.25 && self.appState.partialTranscript.isEmpty {
                    Logger.log("Click accidentale (hold: \(String(format: "%.2f", holdDuration))s) → annullo.")
                    self.speechManager.cancelRecording()
                    self.appState.isRecording = false
                    self.appState.partialTranscript = ""
                    self.appState.audioLevel = 0
                    self.appState.overlayMode = .idle
                } else {
                    Logger.log("Hold confermato (\(String(format: "%.2f", holdDuration))s) → stop registrazione.")
                    self.speechManager.stopRecording()
                    // Non cambiamo overlayMode qui: lo farà onFinalTranscript/onSilence
                }
            }
        }

        // Trascrizione parziale in tempo reale
        speechManager.onPartialTranscript = { [weak self] partialText in
            guard let self else { return }
            self.appState.partialTranscript = partialText
        }

        // Silenzio: nessuna parola riconosciuta nella sessione (o sessione troppo corta)
        // NOTA: con il nuovo SpeechManager, onSilence viene chiamato solo quando
        // stopRequested=true e la trascrizione è vuota. Non scatta più durante hold-to-talk.
        speechManager.onSilence = { [weak self] in
            guard let self else { return }

            if self.isLockedListening {
                // In lock-to-listen il riavvio della sessione avviene internamente
                // a SpeechManager. Questo callback ora non dovrebbe più arrivare in quel contesto,
                // ma lo gestiamo comunque per sicurezza.
                Logger.log("Silenzio in Lock-to-Listen: ignorato (SpeechManager riavvia la sessione autonomamente).")
                return
            }

            Logger.log("Silenzio rilevato → ripristino idle.")
            self.keyUpTimer?.invalidate()
            self.keyUpTimer = nil
            self.appState.partialTranscript = ""
            self.appState.audioLevel = 0
            self.appState.isRecording = false
            self.appState.isProcessing = false
            self.appState.overlayMode = .idle
        }

        // Livello audio in tempo reale → visualizzazione barre
        speechManager.onAudioLevel = { [weak self] level in
            guard let self else { return }
            let current = self.appState.audioLevel
            if level > current {
                self.appState.audioLevel = 0.5 * level + 0.5 * current
            } else {
                self.appState.audioLevel = 0.15 * level + 0.85 * current
            }
        }

        // Trascrizione finale → pulizia + incolla
        speechManager.onFinalTranscript = { [weak self] rawText in
            guard let self else { return }
            Logger.log("onFinalTranscript: \(rawText)")

            // In Lock-to-Listen: incolla il testo intermedio e riavvia l'ascolto
            if self.isLockedListening {
                Logger.log("Lock-to-Listen: trascrizione intermedia pronta, incolla e riavvia microfono.")
                self.appState.overlayMode = .processing
                let glossaryText = self.appState.applyGlossary(to: rawText)

                self.ollamaManager.isModelLoaded(self.appState.ollamaModelName) { [weak self] isLoaded in
                    guard let self else { return }
                    self.appState.processingStatusText = isLoaded ? "Elaborazione..." : "Avvio modello AI..."
                    self.ollamaManager.cleanTranscript(
                        glossaryText,
                        modelName: self.appState.ollamaModelName,
                        temperature: self.appState.temperature,
                        preset: self.appState.aiPreset,
                        customPrompt: self.appState.customPrompt
                    ) { [weak self] cleaned, success in
                        guard let self else { return }
                        if !success { self.appState.triggerOfflineAlert() }
                        if !cleaned.isEmpty {
                            let record = TranscriptionRecord(rawText: rawText, cleanedText: cleaned)
                            self.appState.addRecord(record)
                            PasteManager.paste(cleaned)
                        }
                        // Riavvia l'ascolto solo se ancora in lock
                        if self.isLockedListening {
                            self.appState.overlayMode = .recording
                            self.appState.partialTranscript = ""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                                guard let self, self.isLockedListening else { return }
                                self.speechManager.startRecording()
                            }
                        }
                    }
                }
                return
            }

            // Flusso normale (Hold-to-Talk)
            self.keyUpTimer?.invalidate()
            self.keyUpTimer = nil
            self.appState.isRecording = false
            self.appState.partialTranscript = ""
            self.appState.audioLevel = 0
            self.appState.overlayMode = .processing
            self.appState.isProcessing = true
            self.appState.processingStatusText = "Elaborazione..."

            let glossaryText = self.appState.applyGlossary(to: rawText)
            Logger.log("Testo post-glossario inviato a Ollama: \(glossaryText)")

            self.ollamaManager.isModelLoaded(self.appState.ollamaModelName) { [weak self] isLoaded in
                guard let self else { return }
                self.appState.processingStatusText = isLoaded ? "Elaborazione..." : "Avvio modello AI..."

                self.ollamaManager.cleanTranscript(
                    glossaryText,
                    modelName: self.appState.ollamaModelName,
                    temperature: self.appState.temperature,
                    preset: self.appState.aiPreset,
                    customPrompt: self.appState.customPrompt
                ) { [weak self] cleaned, success in
                    guard let self else { return }
                    self.appState.isProcessing = false
                    self.appState.overlayMode = .idle

                    if !success { self.appState.triggerOfflineAlert() }
                    guard !cleaned.isEmpty else { return }

                    let record = TranscriptionRecord(rawText: rawText, cleanedText: cleaned)
                    self.appState.addRecord(record)
                    PasteManager.paste(cleaned)
                }
            }
        }

        // Hotkey registrato dalla modalità interattiva
        keyboardManager.onHotkeyRecorded = { [weak self] keyCode in
            guard let self else { return }
            Logger.log("Nuovo hotkey registrato: \(keyCode) (\(KeyboardManager.keyName(for: keyCode)))")
            self.appState.hotkeyKeyCode = keyCode
            self.appState.isRecordingHotkey = false
            self.appState.hotkeyRejectionMessage = nil
            self.appState.persistHotkey()
            self.keyboardManager.updateTargetKey(keyCode)
        }

        // Hotkey rifiutato (es. Fn/Globe)
        keyboardManager.onHotkeyRejected = { [weak self] message in
            guard let self else { return }
            self.appState.hotkeyRejectionMessage = message
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.appState.hotkeyRejectionMessage = nil
            }
        }

        // MARK: - Ridimensionamento dinamico overlay
        // Osserva i cambiamenti di stato che influenzano la dimensione della capsula
        // e ridimensiona la finestra overlay di conseguenza.
        appState.$overlayMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.overlayWindow.updateWindowSize()
            }
            .store(in: &cancellables)

        appState.$showOfflineAlert
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.overlayWindow.updateWindowSize()
            }
            .store(in: &cancellables)

        appState.$partialTranscript
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.overlayWindow.updateWindowSize()
            }
            .store(in: &cancellables)
    }

    // MARK: - Actions

    @objc private func showDashboard() {
        refreshOllamaStatus()
        dashboardWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshOllamaStatus() {
        ollamaManager.checkConnection { [weak self] connected in
            guard let self else { return }
            self.appState.isOllamaConnected = connected
            if connected {
                self.ollamaManager.fetchAvailableModels { models in
                    self.appState.availableOllamaModels = models
                    // Se il modello correntemente selezionato non fa parte della lista dei modelli ed essa non è vuota,
                    // potremmo selezionare automaticamente il primo per evitare errori.
                    if !models.isEmpty && !models.contains(self.appState.ollamaModelName) {
                        self.appState.ollamaModelName = models[0]
                    }
                }
            } else {
                self.appState.availableOllamaModels = []
            }
        }
    }

    private func stopLockedRecording() {
        isLockedListening = false
        appState.isRecording = false
        speechManager.stopRecording()
    }

    private func setupMouseMonitors() {
        // Monitor locale per click sinistro (interrompe la registrazione bloccata)
        mouseMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.isLockedListening {
                Logger.log("Mouse click locale rilevato. Interrompo registrazione bloccata.")
                self.stopLockedRecording()
            }
            return event
        }
        
        // Monitor globale per click sinistro (interrompe la registrazione bloccata se l'app è in background)
        mouseMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.isLockedListening {
                Logger.log("Mouse click globale rilevato. Interrompo registrazione bloccata.")
                self.stopLockedRecording()
            }
        }
    }

    @objc private func quitApp() {
        keyboardManager.stop()
        NSApplication.shared.terminate(nil)
    }

    @objc private func handleStartHotkeyRecording() {
        appState.isRecordingHotkey = true
        keyboardManager.startRecordingNextKey()
    }

    @objc private func handleToggleDashboard() {
        if dashboardWindow.isVisible && dashboardWindow.isKeyWindow {
            dashboardWindow.orderOut(nil)
        } else {
            showDashboard()
        }
    }

    @objc private func handleRefreshOllamaNotification() {
        refreshOllamaStatus()
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - PassThroughHostingView

/// Fa passare i click che cadono nel padding della finestra (fuori dalla capsula).
class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    weak var overlayWindow: OverlayWindow?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let window = overlayWindow else {
            return super.hitTest(point)
        }
        let capsule = OverlayWindow.capsuleSize(
            for: window.appState.overlayMode,
            showOfflineAlert: window.appState.showOfflineAlert,
            partialTranscript: window.appState.partialTranscript
        )
        let centerX = bounds.width / 2
        let centerY = bounds.height / 2
        let rect = NSRect(
            x: centerX - capsule.width / 2,
            y: centerY - capsule.height / 2,
            width: capsule.width,
            height: capsule.height
        )
        guard rect.contains(point) else {
            return nil  // Click nel padding → passa attraverso
        }
        return super.hitTest(point)
    }
}
