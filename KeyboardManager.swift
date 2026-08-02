import Cocoa
import ApplicationServices

/// Intercepts the global hotkey through a `CGEventTap`.
///
/// The tap runs on a dedicated run loop thread so it never blocks the main
/// thread. Note that this callback sits in the system-wide event path: it is
/// invoked for every matching key event on the Mac, so it must stay cheap —
/// no disk I/O, no allocation-heavy work.
final class KeyboardManager {

    // MARK: - Callbacks (always delivered on the main thread)
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onHotkeyRecorded: ((CGKeyCode) -> Void)?
    /// Raised when the user presses a key macOS cannot deliver as a hotkey.
    /// The user-facing wording lives in `L10n`, so this carries no string.
    var onHotkeyRejected: (() -> Void)?

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

    // MARK: - Local monitor used while recording a new hotkey (does NOT need Accessibility)
    private var localMonitor: Any?

    private var permissionTimer: Timer?

    init(keyCode: CGKeyCode) {
        self.targetKeyCode = keyCode
    }

    // MARK: - Public Interface

    func updateTargetKey(_ code: CGKeyCode) {
        targetKeyCode = code
    }

    /// Enters hotkey-recording mode.
    ///
    /// Uses an `NSEvent` local monitor rather than the event tap, so the user can
    /// rebind the hotkey before Accessibility has been granted.
    func startRecordingNextKey() {
        isKeyDown = false
        isRecordingNextKey = true
        Logger.log("Hotkey recording mode enabled.")

        stopRecordingMonitors()

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecordingNextKey else { return event }
            if self.captureKeyFromNSEvent(event) {
                return nil // Swallow the event
            }
            return event
        }

        Logger.log("Local monitor for hotkey recording installed.")
    }

    /// Starts the event tap on a dedicated thread.
    func start() {
        guard !isRunning else { return }

        let trusted = AXIsProcessTrusted()
        Logger.log("AXIsProcessTrusted: \(trusted)")

        if !trusted {
            Logger.log("Accessibility permission not granted. Starting silent polling.")
            // Deliberately no system prompt here: onboarding in DashboardView owns that flow.
            startPermissionPolling()
            return
        }

        startEventTap()
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
        if let source = runLoopSource, let loop = tapRunLoop {
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        if let loop = tapRunLoop {
            CFRunLoopStop(loop)
        }
        eventTap = nil
        runLoopSource = nil
        tapRunLoop = nil
        Logger.log("Keyboard hook stopped.")
    }

    // MARK: - Hotkey Recording

    private func stopRecordingMonitors() {
        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }
    }

    /// Attempts to capture a key from an `NSEvent`. Returns true once one is recorded.
    private func captureKeyFromNSEvent(_ event: NSEvent) -> Bool {
        var keyCode = CGKeyCode(event.keyCode)

        if event.type == .flagsChanged {
            let flags = event.modifierFlags
            // Derive the modifier from the flags rather than the key code: on recent
            // MacBooks key code 179 (Fn/Globe) is emitted as a phantom event whenever
            // any modifier is pressed.
            if flags.contains(.option) {
                // Distinguish left/right: 58 = left, 61 = right. Keep the reported
                // code when it is already a valid Option key, otherwise assume right.
                keyCode = (keyCode == 58) ? 58 : 61
            } else if flags.contains(.command) {
                keyCode = (keyCode == 55) ? 55 : 54
            } else if flags.contains(.control) {
                keyCode = (keyCode == 59) ? 59 : 62
            } else if flags.contains(.shift) {
                keyCode = (keyCode == 56) ? 56 : 60
            } else {
                // No modifier flag set (e.g. a key release) → ignore
                return false
            }
        } else if event.type != .keyDown {
            return false
        }

        // Reject key codes macOS will not deliver reliably.
        if keyCode == 179 || keyCode == 63 { // 179 = Fn/Globe, 63 = legacy fn
            Logger.log("Fn/Globe key ignored (unusable as a hotkey).")
            DispatchQueue.main.async { [weak self] in
                self?.onHotkeyRejected?()
            }
            return false
        }

        isRecordingNextKey = false
        stopRecordingMonitors()
        Logger.log("New hotkey recorded: keyCode=\(keyCode)")
        DispatchQueue.main.async { [weak self] in
            self?.onHotkeyRecorded?(keyCode)
        }
        return true
    }

    // MARK: - Event Tap Lifecycle

    /// Polls for the Accessibility permission and starts the tap as soon as it is granted,
    /// so the user does not have to relaunch the app after flipping the toggle.
    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.permissionTimer = nil
                Logger.log("Accessibility permission granted. Starting event tap.")
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
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<KeyboardManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleTapEvent(type: type, event: event)
            },
            userInfo: selfPointer
        ) else {
            Logger.log("ERROR: could not create the event tap even with permission granted.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        isRunning = true

        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            let loop = CFRunLoopGetCurrent()
            self.tapRunLoop = loop
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            Logger.log("Event tap ACTIVE on dedicated thread. Target key code: \(self.targetKeyCode)")
            CFRunLoopRun()
        }
        thread.name = "com.attilio.mywispr.keyboard"
        thread.qualityOfService = .userInteractive
        thread.start()
        tapThread = thread
    }

    // MARK: - CGEvent Handling (runs on the tap thread)

    /// Hot path: called for every key and modifier event on the system.
    /// Everything before the `targetKeyCode` check must stay allocation- and I/O-free.
    private func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // While the user is rebinding, the local NSEvent monitor owns the
        // keystroke. The tap must stay out of the way, or pressing the *current*
        // hotkey to replace it would also start a dictation.
        guard !isRecordingNextKey else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        guard keyCode == targetKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let isPressedNow = isKeyCurrentlyPressed(keyCode: keyCode, type: type, event: event)

        if isPressedNow && !isKeyDown {
            isKeyDown = true
            DispatchQueue.main.async { [weak self] in
                Logger.log("Hotkey DOWN")
                self?.onKeyDown?()
            }
        } else if !isPressedNow && isKeyDown {
            isKeyDown = false
            DispatchQueue.main.async { [weak self] in
                Logger.log("Hotkey UP")
                self?.onKeyUp?()
            }
        }

        return Unmanaged.passUnretained(event)
    }

    /// Modifier keys report their state through the event flags rather than
    /// keyDown/keyUp, so they need separate handling.
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
}
