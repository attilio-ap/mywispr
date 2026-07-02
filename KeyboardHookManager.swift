import Cocoa
import ApplicationServices

class KeyboardHookManager: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    
    @Published var isListening = false
    @Published var selectedKeyCode: CGKeyCode = 61 // Default: Right Option (61)
    @Published var isRecordingHotkey = false
    
    private var isKeyPressed = false
    
    init() {
        let savedKey = UserDefaults.standard.integer(forKey: "selected_hotkey")
        if savedKey != 0 {
            self.selectedKeyCode = CGKeyCode(savedKey)
        }
        Logger.log("Inizializzato KeyboardHookManager. Tasto configurato: \(selectedKeyCode) (\(keyName(for: selectedKeyCode)))")
    }
    
    func startRecording() {
        DispatchQueue.main.async {
            self.isRecordingHotkey = true
            Logger.log("Inizio registrazione nuovo hotkey. In attesa di input tastiera...")
        }
    }
    
    func start() {
        guard eventTap == nil else { return }
        
        // Ascoltiamo flagsChanged (per modificatori) e keyDown/keyUp (per tasti normali)
        let eventMask = (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue)
        
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        
        Logger.log("Tentativo di avvio dell'Event Tap...")
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<KeyboardHookManager>.fromOpaque(refcon).takeUnretainedValue()
                
                // Se stiamo registrando l'hotkey, consumiamo l'evento così non scrive a schermo il tasto premuto
                if manager.isRecordingHotkey {
                    manager.handleEvent(event, type: type)
                    return nil // Consuma l'evento per evitare che scriva a schermo durante la config
                }
                
                manager.handleEvent(event, type: type)
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer
        ) else {
            Logger.log("ERRORE CRITICO: Impossibile creare l'Event Tap. I permessi di Accessibilità non sono attivi per questa build!")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let runLoopSource = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Logger.log("Keyboard hook avviato con successo. In ascolto per il tasto con codice: \(selectedKeyCode)")
        }
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        Logger.log("Keyboard hook arrestato.")
    }
    
    private func handleEvent(_ event: CGEvent, type: CGEventType) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        
        // 1. Se siamo in modalità di registrazione hotkey
        if isRecordingHotkey {
            let shouldRecord: Bool
            if type == .flagsChanged {
                // Per i modificatori, controlliamo che almeno un flag sia premuto
                let flags = event.flags
                shouldRecord = flags.contains(.maskAlternate) || flags.contains(.maskCommand) ||
                               flags.contains(.maskControl) || flags.contains(.maskShift)
            } else if type == .keyDown {
                shouldRecord = true
            } else {
                shouldRecord = false
            }
            
            if shouldRecord {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.selectedKeyCode = keyCode
                    UserDefaults.standard.set(Int(keyCode), forKey: "selected_hotkey")
                    self.isRecordingHotkey = false
                    Logger.log("Nuovo tasto registrato: \(keyCode) (\(self.keyName(for: keyCode)))")
                }
            }
            return
        }
        
        // 2. Comportamento normale (ascolto dell'hotkey)
        guard keyCode == selectedKeyCode else { return }
        
        let isModifier = isModifierKey(keyCode)
        let isPressedNow: Bool
        
        if isModifier {
            let flags = event.flags
            switch keyCode {
            case 58, 61: // Option
                isPressedNow = flags.contains(.maskAlternate)
            case 55, 54: // Command
                isPressedNow = flags.contains(.maskCommand)
            case 59, 62: // Control
                isPressedNow = flags.contains(.maskControl)
            case 56, 60: // Shift
                isPressedNow = flags.contains(.maskShift)
            case 57: // Caps Lock
                isPressedNow = flags.contains(.maskAlphaShift)
            default:
                isPressedNow = false
            }
        } else {
            // Per i tasti normali, ricaviamo lo stato dall'evento keyDown o keyUp
            if type == .keyDown {
                isPressedNow = true
            } else if type == .keyUp {
                isPressedNow = false
            } else {
                return
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if isPressedNow && !self.isKeyPressed {
                self.isKeyPressed = true
                self.isListening = true
                Logger.log("Hotkey premuto: \(self.keyName(for: keyCode)) GIÙ")
                self.onKeyDown?()
            } else if !isPressedNow && self.isKeyPressed {
                self.isKeyPressed = false
                self.isListening = false
                Logger.log("Hotkey rilasciato: \(self.keyName(for: keyCode)) SU")
                self.onKeyUp?()
            }
        }
    }
    
    private func isModifierKey(_ code: CGKeyCode) -> Bool {
        let modifiers: Set<CGKeyCode> = [54, 55, 56, 57, 58, 59, 60, 61, 62]
        return modifiers.contains(code)
    }
    
    func keyName(for code: CGKeyCode) -> String {
        switch code {
        case 61: return "Option Destro"
        case 58: return "Option Sinistro"
        case 54: return "Command Destro"
        case 55: return "Command Sinistro"
        case 59: return "Control Sinistro"
        case 62: return "Control Destro"
        case 56: return "Shift Sinistro"
        case 60: return "Shift Destro"
        case 57: return "Caps Lock"
        case 36: return "Invio"
        case 49: return "Spazio"
        case 53: return "Esc"
        case 48: return "Tab"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default:
            return "Tasto [Codice \(code)]"
        }
    }
}
