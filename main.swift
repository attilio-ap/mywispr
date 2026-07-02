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
            name: .startHotkeyRecording,
            object: nil
        )

        // Osserva richiesta di toggle della Dashboard
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleToggleDashboard),
            name: NSNotification.Name("mywispr.toggleDashboard"),
            object: nil
        )

        // Mostra la notch in sovrimpressione permanente
        overlayWindow.showCentered()
        
        Logger.log("MyWispr avviato. AXIsProcessTrusted: \(AXIsProcessTrusted())")
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardManager.stop()
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
        hostingView.checkHit = { [weak self] point in
            guard let self else { return false }
            return self.overlayWindow.isPointInsideCapsule(point)
        }
        
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
        // Hotkey giù → avvia registrazione
        keyboardManager.onKeyDown = { [weak self] in
            guard let self else { return }
            guard self.appState.hasSpeechPermission && self.appState.hasMicrophonePermission else {
                Logger.log("onKeyDown ignorato: permessi mancanti.")
                self.showDashboard()
                return
            }
            Logger.log("onKeyDown ricevuto.")
            self.appState.isRecording = true
            self.appState.overlayMode = .recording
            self.speechManager.startRecording()
        }

        // Hotkey su → ferma registrazione
        keyboardManager.onKeyUp = { [weak self] in
            guard let self else { return }
            Logger.log("onKeyUp ricevuto.")
            self.speechManager.stopRecording()
        }

        // Caso in cui la registrazione vocale si arresta senza parole parlate
        speechManager.onSilence = { [weak self] in
            guard let self else { return }
            Logger.log("Rilevato silenzio, ripristino notch idle.")
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
            self.appState.isRecording = false
            self.appState.audioLevel = 0
            self.appState.overlayMode = .processing
            self.appState.isProcessing = true
 
            // Applica il Glossario prima di inviare a Ollama
            let glossaryText = self.appState.applyGlossary(to: rawText)
            Logger.log("Testo post-glossario inviato a Ollama: \(glossaryText)")

            self.ollamaManager.cleanTranscript(
                glossaryText,
                modelName: self.appState.ollamaModelName,
                temperature: self.appState.temperature,
                preset: self.appState.aiPreset,
                customPrompt: self.appState.customPrompt
            ) { cleaned in
                self.appState.isProcessing = false
                self.appState.overlayMode = .idle
 
                guard !cleaned.isEmpty else { return }
 
                // Aggiungi alla cronologia (usando rawText originale per consentire il diff!)
                let record = TranscriptionRecord(rawText: rawText, cleanedText: cleaned)
                self.appState.addRecord(record)
 
                // Incolla nella finestra attiva
                PasteManager.paste(cleaned)
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
            // Il messaggio scompare dopo 4 secondi
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                self.appState.hotkeyRejectionMessage = nil
            }
        }
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
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

// MARK: - PassThroughHostingView

class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var checkHit: ((NSPoint) -> Bool)?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let checkHit = checkHit, !checkHit(point) {
            return nil
        }
        return super.hitTest(point)
    }
}
