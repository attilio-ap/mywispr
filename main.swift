import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Core Objects (non-UI)
    private let appState = AppState()
    private var keyboardManager: KeyboardManager!
    private var speechManager: SpeechManager!
    private var ollamaManager: OllamaManager!

    // MARK: - Windows
    private var statusItem: NSStatusItem!
    private var overlayWindow: OverlayWindow!
    private var dashboardWindow: NSWindow!

    // MARK: - Interaction State (hold-to-talk / lock-to-listen)

    /// Maximum gap between two presses to count as a double-press.
    private static let doublePressWindow: TimeInterval = 0.35

    /// How long to wait after a key release before committing to "this was a single press".
    /// Slightly shorter than `doublePressWindow` so the two cannot race.
    private static let singlePressConfirmDelay: TimeInterval = 0.32

    /// A press shorter than this with nothing transcribed is treated as accidental.
    private static let accidentalTapThreshold: TimeInterval = 0.25

    private var lastKeyDownTime: Date?
    private var keyUpTimer: Timer?
    private var isLockedListening = false
    private var mouseMonitorLocal: Any?
    private var mouseMonitorGlobal: Any?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupMenuBar()

        // Initialise the managers from the persisted state
        keyboardManager = KeyboardManager(keyCode: appState.hotkeyKeyCode)
        ollamaManager = OllamaManager()
        speechManager = SpeechManager(language: appState.dictationLanguage)
        appState.isOnDeviceRecognition = speechManager.isOnDeviceRecognition

        // Apply the persisted light/dark choice before any window is shown.
        appState.appearance.apply()

        setupOverlayWindow()
        setupDashboardWindow()
        setupCallbacks()
        setupNotificationObservers()

        // Request permissions, and open the dashboard onboarding if any are missing
        speechManager.requestPermissions { [weak self] speech, mic in
            guard let self else { return }
            self.appState.hasSpeechPermission = speech
            self.appState.hasMicrophonePermission = mic

            if !speech || !mic || !AXIsProcessTrusted() {
                self.showDashboard()
            }
        }

        keyboardManager.start()
        refreshOllamaStatus()

        // Show the persistent overlay notch
        overlayWindow.showCentered()

        setupMouseMonitors()

        Logger.log("MyWispr launched. AXIsProcessTrusted: \(AXIsProcessTrusted())")
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

        // App menu (macOS requires one for Cmd+Q and friends)
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "MyWispr")
        let quitItem = NSMenuItem(title: appState.l10n.menuQuitApp, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        appMenu.addItem(quitItem)
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        // Edit menu (enables Cmd+C/V/X/A inside the dashboard text fields)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: appState.l10n.menuCut,       action: #selector(NSText.cut(_:)),       keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: appState.l10n.menuCopy,      action: #selector(NSText.copy(_:)),      keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: appState.l10n.menuPaste,     action: #selector(NSText.paste(_:)),     keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: appState.l10n.menuSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupMenuBar() {
        // Reuse the existing item when rebuilding after a language change,
        // otherwise a second icon would appear in the menu bar.
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "MyWispr")
        }
        let menu = NSMenu()

        let openItem = NSMenuItem(title: appState.l10n.menuOpenDashboard, action: #selector(showDashboard), keyEquivalent: "d")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: appState.l10n.menuQuit, action: #selector(quitApp), keyEquivalent: "q")
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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        dashboardWindow.title = "MyWispr"
        dashboardWindow.isReleasedWhenClosed = false
        // Let the NSVisualEffectView inside the view hierarchy blur what is
        // behind the window, rather than sitting on an opaque backing.
        dashboardWindow.titlebarAppearsTransparent = true
        dashboardWindow.isOpaque = false
        dashboardWindow.backgroundColor = .clear
        let dashView = DashboardView().environmentObject(appState)
        dashboardWindow.contentView = NSHostingView(rootView: dashView)
        dashboardWindow.center()
    }

    private func setupNotificationObservers() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleStartHotkeyRecording),
                           name: .mywisprStartHotkeyRecording, object: nil)
        center.addObserver(self, selector: #selector(handleToggleDashboard),
                           name: .mywisprToggleDashboard, object: nil)
        center.addObserver(self, selector: #selector(handleRefreshOllamaNotification),
                           name: .mywisprRefreshOllama, object: nil)
    }

    // MARK: - Callback Wiring

    private func setupCallbacks() {
        setupHotkeyCallbacks()
        setupSpeechCallbacks()
        setupOverlayResizing()
        setupLanguageObserver()
    }

    /// Reacts to a language change: reconfigure the recogniser and rebuild the
    /// AppKit menus, which are plain strings and do not update themselves.
    private func setupLanguageObserver() {
        appState.$dictationLanguage
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] newLanguage in
                guard let self else { return }
                // `reconfigure` cancels any live session before switching.
                self.speechManager.reconfigure(for: newLanguage)
                // On-device availability is per-locale, so re-publish it.
                self.appState.isOnDeviceRecognition = self.speechManager.isOnDeviceRecognition
                self.resetToIdle()
            }
            .store(in: &cancellables)

        appState.$uiLanguage
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.setupMainMenu()
                self?.setupMenuBar()
            }
            .store(in: &cancellables)
    }

    // ---------------------------------------------------------------
    // Two interaction modes share one hotkey:
    //
    // A — HOLD-TO-TALK:
    //   Press and hold  → start recording immediately
    //   Release         → stop and process
    //
    // B — LOCK-TO-LISTEN (hands free):
    //   Two quick presses → stay listening continuously. The second press does
    //   NOT start a second session; the one already running is kept.
    //   To exit: press the hotkey again, or left-click anywhere.
    // ---------------------------------------------------------------
    private func setupHotkeyCallbacks() {
        keyboardManager.onKeyDown = { [weak self] in
            guard let self else { return }
            guard self.appState.hasSpeechPermission && self.appState.hasMicrophonePermission else {
                Logger.log("onKeyDown ignored: permissions missing.")
                self.showDashboard()
                return
            }

            // Already locked? This press exits lock-to-listen.
            if self.isLockedListening {
                Logger.log("Hotkey DOWN while locked → leaving lock-to-listen.")
                self.stopLockedRecording()
                return
            }

            let now = Date()
            let timeSinceLast = self.lastKeyDownTime.map { now.timeIntervalSince($0) } ?? .infinity
            self.lastKeyDownTime = now

            if timeSinceLast < Self.doublePressWindow {
                // DOUBLE PRESS → enter lock-to-listen.
                // Cancel the first press's key-up timer so the running session is not stopped.
                self.keyUpTimer?.invalidate()
                self.keyUpTimer = nil
                Logger.log("Double press detected (\(String(format: "%.2f", timeSinceLast))s) → lock-to-listen active.")
                self.isLockedListening = true
                // The session started by the first press simply keeps running.
            } else {
                // FIRST PRESS → classic hold-to-talk.
                if self.appState.isRecording {
                    Logger.log("WARN: isRecording was true when starting a new hold-to-talk. Discarding the stale session.")
                    self.speechManager.cancelRecording()
                    self.appState.isProcessing = false
                }
                Logger.log("Hotkey DOWN (hold-to-talk).")
                self.appState.partialTranscript = ""
                self.appState.audioLevel = 0
                self.appState.isRecording = true
                self.appState.overlayMode = .recording
                self.speechManager.startRecording()
            }
        }

        keyboardManager.onKeyUp = { [weak self] in
            guard let self else { return }

            // In lock-to-listen the key release means nothing.
            if self.isLockedListening {
                Logger.log("Hotkey UP ignored (lock-to-listen active).")
                return
            }

            let keyUpTime = Date()

            // Wait out the double-press window before committing to a single press.
            // A second key-down within the window invalidates this timer.
            self.keyUpTimer?.invalidate()
            self.keyUpTimer = Timer.scheduledTimer(withTimeInterval: Self.singlePressConfirmDelay, repeats: false) { [weak self] _ in
                guard let self, !self.isLockedListening else { return }

                // Already finalised elsewhere (e.g. onSilence fired) — avoid a double finalise.
                guard self.appState.isRecording else {
                    Logger.log("keyUpTimer: not recording, ignoring.")
                    return
                }

                let holdDuration = self.lastKeyDownTime.map { keyUpTime.timeIntervalSince($0) } ?? 1.0

                if holdDuration < Self.accidentalTapThreshold && self.appState.partialTranscript.isEmpty {
                    // Very short press with nothing said → the user brushed the key.
                    Logger.log("Accidental tap (held \(String(format: "%.2f", holdDuration))s) → cancelling.")
                    self.speechManager.cancelRecording()
                    self.resetToIdle()
                } else {
                    Logger.log("Hold confirmed (\(String(format: "%.2f", holdDuration))s) → stopping recording.")
                    self.speechManager.stopRecording()
                    // Leave overlayMode alone: onFinalTranscript / onSilence will set it.
                }
            }
        }

        keyboardManager.onHotkeyRecorded = { [weak self] keyCode in
            guard let self else { return }
            Logger.log("Hotkey applied and persisted: \(keyCode)")
            self.appState.hotkeyKeyCode = keyCode
            self.appState.isRecordingHotkey = false
            self.appState.hotkeyRejectionMessage = nil
            self.appState.persistHotkey()
            self.keyboardManager.updateTargetKey(keyCode)
        }

        keyboardManager.onHotkeyRejected = { [weak self] in
            guard let self else { return }
            self.appState.hotkeyRejectionMessage = self.appState.l10n.hotkeyFnRejected
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.appState.hotkeyRejectionMessage = nil
            }
        }
    }

    private func setupSpeechCallbacks() {
        speechManager.onPartialTranscript = { [weak self] partialText in
            self?.appState.partialTranscript = partialText
        }

        // No speech recognised in the session.
        // SpeechManager only raises this once a stop was requested and the transcript
        // is empty, so it no longer fires mid hold-to-talk.
        speechManager.onSilence = { [weak self] in
            guard let self else { return }

            if self.isLockedListening {
                // SpeechManager restarts the session itself while locked.
                Logger.log("Silence while locked: ignored (SpeechManager restarts on its own).")
                return
            }

            Logger.log("Silence detected → returning to idle.")
            self.keyUpTimer?.invalidate()
            self.keyUpTimer = nil
            self.appState.isProcessing = false
            self.resetToIdle()
        }

        // Live audio level → equaliser bars.
        // Asymmetric smoothing: rise quickly so the bars feel responsive,
        // fall slowly so they decay smoothly instead of flickering.
        speechManager.onAudioLevel = { [weak self] level in
            guard let self else { return }
            let current = self.appState.audioLevel
            if level > current {
                self.appState.audioLevel = 0.5 * level + 0.5 * current
            } else {
                self.appState.audioLevel = 0.15 * level + 0.85 * current
            }
        }

        speechManager.onFinalTranscript = { [weak self] rawText in
            guard let self else { return }
            Logger.logSensitive("onFinalTranscript", rawText)

            if self.isLockedListening {
                self.handleLockedTranscript(rawText)
            } else {
                self.handleHoldToTalkTranscript(rawText)
            }
        }
    }

    /// Keeps the overlay window sized to whatever the capsule currently needs.
    private func setupOverlayResizing() {
        let resize: (Any) -> Void = { [weak self] _ in
            self?.overlayWindow.updateWindowSize()
        }

        appState.$overlayMode.receive(on: RunLoop.main).sink(receiveValue: resize).store(in: &cancellables)
        appState.$showOfflineAlert.receive(on: RunLoop.main).sink(receiveValue: resize).store(in: &cancellables)
        appState.$partialTranscript.receive(on: RunLoop.main).sink(receiveValue: resize).store(in: &cancellables)
    }

    // MARK: - Transcript Processing

    /// Lock-to-listen: paste this chunk, then immediately resume listening.
    private func handleLockedTranscript(_ rawText: String) {
        Logger.log("Lock-to-listen: chunk ready, pasting and restarting the microphone.")
        appState.overlayMode = .processing

        processAndPaste(rawText) { [weak self] in
            guard let self, self.isLockedListening else { return }
            self.appState.overlayMode = .recording
            self.appState.partialTranscript = ""
            // Small gap so the audio engine has fully torn down before restarting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.isLockedListening else { return }
                self.speechManager.startRecording()
            }
        }
    }

    /// Hold-to-talk: paste once, then return to idle.
    private func handleHoldToTalkTranscript(_ rawText: String) {
        keyUpTimer?.invalidate()
        keyUpTimer = nil
        appState.isRecording = false
        appState.partialTranscript = ""
        appState.audioLevel = 0
        appState.overlayMode = .processing
        appState.isProcessing = true

        processAndPaste(rawText) { [weak self] in
            guard let self else { return }
            self.appState.isProcessing = false
            self.appState.overlayMode = .idle
        }
    }

    /// Shared pipeline: glossary → Ollama cleanup → history → paste.
    /// `completion` runs on the main thread once the text has been handled.
    private func processAndPaste(_ rawText: String, completion: @escaping () -> Void) {
        appState.processingStatusText = appState.l10n.overlayProcessing

        let glossaryText = appState.applyGlossary(to: rawText)
        Logger.logSensitive("Text sent to Ollama (post-glossary)", glossaryText)

        // Loading a cold model can take seconds — tell the user which is happening.
        ollamaManager.isModelLoaded(appState.ollamaModelName) { [weak self] isLoaded in
            guard let self else { return }
            self.appState.processingStatusText = isLoaded ? self.appState.l10n.overlayProcessing : self.appState.l10n.overlayStartingModel

            self.ollamaManager.cleanTranscript(
                glossaryText,
                modelName: self.appState.ollamaModelName,
                temperature: self.appState.temperature,
                preset: self.appState.aiPreset,
                customPrompt: self.appState.customPrompt,
                language: self.appState.dictationLanguage
            ) { [weak self] cleaned, success in
                guard let self else { return }

                // Ollama unreachable: warn, but still paste the raw transcript.
                if !success { self.appState.triggerOfflineAlert() }

                if !cleaned.isEmpty {
                    self.appState.addRecord(TranscriptionRecord(rawText: rawText, cleanedText: cleaned))
                    PasteManager.paste(cleaned)
                }
                completion()
            }
        }
    }

    /// Clears the transient recording state and collapses the overlay.
    private func resetToIdle() {
        appState.isRecording = false
        appState.partialTranscript = ""
        appState.audioLevel = 0
        appState.overlayMode = .idle
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

            guard connected else {
                self.appState.availableOllamaModels = []
                self.appState.loadedOllamaModels = []
                return
            }

            self.ollamaManager.fetchAvailableModels { [weak self] models in
                guard let self else { return }
                self.appState.availableOllamaModels = models
                // If the selected model is no longer installed, fall back to the first one
                // so the app is not stuck pointing at something that cannot answer.
                if !models.isEmpty && !models.contains(self.appState.ollamaModelName) {
                    self.appState.ollamaModelName = models[0]
                }
            }

            self.ollamaManager.fetchLoadedModels { [weak self] loaded in
                self?.appState.loadedOllamaModels = loaded
            }
        }
    }

    private func stopLockedRecording() {
        isLockedListening = false
        appState.isRecording = false
        speechManager.stopRecording()
    }

    /// Left-clicking anywhere is an escape hatch out of lock-to-listen.
    private func setupMouseMonitors() {
        // Local monitor: clicks inside MyWispr's own windows.
        mouseMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if self.isLockedListening {
                Logger.log("Local mouse click detected. Stopping locked recording.")
                self.stopLockedRecording()
            }
            return event
        }

        // Global monitor: clicks in any other app.
        mouseMonitorGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.isLockedListening {
                Logger.log("Global mouse click detected. Stopping locked recording.")
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

// MARK: - PassThroughHostingView

/// Lets clicks that land in the window's transparent padding fall through to
/// whatever is underneath, so the overlay only intercepts the capsule itself.
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
        let rect = NSRect(
            x: bounds.midX - capsule.width / 2,
            y: bounds.midY - capsule.height / 2,
            width: capsule.width,
            height: capsule.height
        )
        guard rect.contains(point) else {
            return nil  // Click in the padding → pass through
        }
        return super.hitTest(point)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
