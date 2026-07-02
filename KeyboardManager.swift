import Cocoa
import ApplicationServices

/// Gestisce l'intercettazione globale della tastiera tramite CGEventTap.
/// Il tap viene eseguito su un thread dedicato per non bloccare il main thread.
final class KeyboardManager {

    // MARK: - Callbacks (vengono chiamati sul main thread)
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onHotkeyRecorded: ((CGKeyCode) -> Void)?
    var onHotkeyRejected: ((String) -> Void)?

    // MARK: - State
    private(set) var isRunning = false
    private var isKeyDown = false
    private var targetKeyCode: CGKeyCode
    private var isRecordingNextKey = false

    // MARK: - Event Tap
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    
    // MARK: - Local monitor per registrazione hotkey (NON richiede Accessibilità)
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(keyCode: CGKeyCode) {
        self.targetKeyCode = keyCode
    }

    // MARK: - Public Interface

    func updateTargetKey(_ code: CGKeyCode) {
        targetKeyCode = code
    }

    /// Entra in modalità di registrazione hotkey.
    /// Usa NSEvent monitor locale + globale (NON richiede Accessibilità).
    func startRecordingNextKey() {
        isKeyDown = false
        isRecordingNextKey = true
        Logger.log("Modalità registrazione hotkey attivata.")
        
        // Rimuovi i monitor precedenti se ce ne sono
        stopRecordingMonitors()
        
        // Monitor LOCALE (cattura tasti quando la nostra finestra è in primo piano)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecordingNextKey else { return event }
            if self.captureKeyFromNSEvent(event) {
                return nil // Consuma l'evento
            }
            return event
        }
        
        Logger.log("Monitor locale per registrazione hotkey installato.")
    }
    
    private func stopRecordingMonitors() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }
    }
    
    /// Tenta di catturare il tasto da un NSEvent. Ritorna true se registrato con successo.
    private func captureKeyFromNSEvent(_ event: NSEvent) -> Bool {
        var keyCode = CGKeyCode(event.keyCode)
        
        if event.type == .flagsChanged {
            let flags = event.modifierFlags
            // Determina il modificatore corretto dai flag, non dal keyCode.
            // Su MacBook recenti, il keyCode 179 (Fn/Globe) viene emesso
            // come evento fantasma quando si preme qualsiasi modificatore.
            if flags.contains(.option) {
                // Distingui sinistro/destro: keyCode 58=left, 61=right.
                // Se il keyCode originale è un Option valido, usalo. Altrimenti default a 61.
                keyCode = (keyCode == 58) ? 58 : 61
            } else if flags.contains(.command) {
                keyCode = (keyCode == 55) ? 55 : 54
            } else if flags.contains(.control) {
                keyCode = (keyCode == 59) ? 59 : 62
            } else if flags.contains(.shift) {
                keyCode = (keyCode == 56) ? 56 : 60
            } else {
                // Nessun flag modificatore attivo (es. rilascio di un tasto) → ignora
                return false
            }
        } else if event.type != .keyDown {
            return false
        }
        
        // Filtra keyCode inutilizzabili
        if keyCode == 179 || keyCode == 63 { // 179=Fn/Globe, 63=fn legacy
            Logger.log("Tasto Fn/Globe ignorato (non utilizzabile come hotkey).")
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyRejected?("Il tasto Fn/Globe non è supportato da macOS come hotkey. Scegli un altro tasto (es. Option, Ctrl, Shift).")
            }
            return false
        }
        
        isRecordingNextKey = false
        stopRecordingMonitors()
        Logger.log("Nuovo hotkey registrato via NSEvent: keyCode=\(keyCode) (\(KeyboardManager.keyName(for: keyCode)))")
        DispatchQueue.main.async { [weak self] in
            self?.onHotkeyRecorded?(keyCode)
        }
        return true
    }

    /// Avvia l'event tap su un thread dedicato.
    func start() {
        guard !isRunning else { return }
        
        let trusted = AXIsProcessTrusted()
        Logger.log("AXIsProcessTrusted: \(trusted)")
        
        if !trusted {
            Logger.log("Permessi di Accessibilita non concessi. Avvio polling silenzioso.")
            // NON mostrare il popup qui: viene gestito dall'onboarding in DashboardView
            startPermissionPolling()
            return
        }
        
        startEventTap()
    }
    
    /// Chiede i permessi di Accessibilit\u00e0 tramite il popup di sistema.
    /// Va chiamato SOLO UNA VOLTA dall'onboarding, non automaticamente.
    func requestAccessibilityPermission() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private var permissionTimer: Timer?
    
    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.permissionTimer = nil
                Logger.log("Permessi di Accessibilita concessi! Avvio Event Tap.")
                self.startEventTap()
            }
        }
    }
    
    private func startEventTap() {
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) |
                                     (1 << CGEventType.keyDown.rawValue) |
                                     (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<KeyboardManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleTapEvent(type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            Logger.log("ERRORE: Impossibile creare l'Event Tap anche con permessi concessi.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        isRunning = true

        // Avvia il tap su un thread dedicato
        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(self.tapRunLoop!, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Logger.log("Event Tap ATTIVO su thread dedicato. Tasto target: \(self.targetKeyCode) (\(KeyboardManager.keyName(for: self.targetKeyCode)))")
            CFRunLoopRun()
        }
        thread.name = "com.attilio.mywispr.keyboard"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil
        stopRecordingMonitors()
        
        guard isRunning else { return }
        isRunning = false

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let loop = tapRunLoop {
            CFRunLoopStop(loop)
        }
        if let source = runLoopSource, let loop = tapRunLoop {
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        Logger.log("Keyboard hook fermato.")
    }

    // MARK: - CGEvent Handling (chiamato sul tap thread)

    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Log di debug per TUTTI gli eventi flagsChanged (utile per diagnostica)
        if type == .flagsChanged {
            Logger.log("[TAP] flagsChanged keyCode=\(keyCode) flags=\(event.flags.rawValue)")
        }

        // Comportamento normale: controlla solo il tasto target
        guard keyCode == targetKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let isPressedNow = isKeyCurrentlyPressed(keyCode: keyCode, type: type, event: event)

        if isPressedNow && !isKeyDown {
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in
                Logger.log("Hotkey GIÙ")
                self?.onKeyDown?()
            }
        } else if !isPressedNow && isKeyDown {
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in
                Logger.log("Hotkey SU")
                self?.onKeyUp?()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func isKeyCurrentlyPressed(keyCode: CGKeyCode, type: CGEventType, event: CGEvent) -> Bool {
        if isModifierKey(keyCode) {
            let flags = event.flags
            switch keyCode {
            case 58, 61: return flags.contains(.maskAlternate)
            case 55, 54: return flags.contains(.maskCommand)
            case 59, 62: return flags.contains(.maskControl)
            case 56, 60: return flags.contains(.maskShift)
            case 57:     return flags.contains(.maskAlphaShift)
            default:     return false
            }
        } else {
            return type == .keyDown
        }
    }

    private func isModifierKey(_ code: CGKeyCode) -> Bool {
        return [54, 55, 56, 57, 58, 59, 60, 61, 62].contains(code)
    }

    // MARK: - Key Names

    static func keyName(for code: CGKeyCode) -> String {
        switch code {
        case 61: return "Option Destro"
        case 58: return "Option Sinistro"
        case 54: return "Command Destro"
        case 55: return "Command Sinistro"
        case 59: return "Ctrl Sinistro"
        case 62: return "Ctrl Destro"
        case 56: return "Shift Sinistro"
        case 60: return "Shift Destro"
        case 57: return "Caps Lock"
        case 36: return "Invio"
        case 49: return "Spazio"
        case 53: return "Esc"
        case 48: return "Tab"
        case 122: return "F1"
        case 120: return "F2"
        case 99:  return "F3"
        case 118: return "F4"
        case 96:  return "F5"
        case 97:  return "F6"
        case 98:  return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:  return "Tasto [\(code)]"
        }
    }
}
