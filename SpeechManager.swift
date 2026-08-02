import Foundation
import Speech
import AVFoundation
import Accelerate

/// Handles microphone capture and speech transcription via `SFSpeechRecognizer`.
///
/// **On-device recognition.** When the selected locale supports it, transcription
/// runs entirely on the Mac and no audio leaves the machine. If the locale's
/// on-device model is not installed, `SFSpeechRecognizer` falls back to Apple's
/// servers — `isOnDeviceRecognition` reports which mode is actually in use so the
/// UI can tell the user the truth rather than assuming.
final class SpeechManager {

    var onFinalTranscript: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onSilence: (() -> Void)?

    // Permissions — checked at init, refreshed through the callback
    private(set) var hasSpeechPermission = false
    private(set) var hasMicrophonePermission = false

    /// True when transcription runs fully on-device (no audio sent to Apple).
    ///
    /// This is evaluated per locale: the offline model may be installed for one
    /// language and not another, so it changes when the language changes.
    private(set) var isOnDeviceRecognition: Bool = false

    /// Language currently configured for recognition.
    private(set) var language: AppLanguage

    /// True while the audio engine is capturing.
    var isBusy: Bool { audioEngine.isRunning }

    // Internals
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var lastTranscript = ""
    private var tapInstalled = false

    /// Set when the caller explicitly asks to stop (key up).
    ///
    /// While this is false a final result is never delivered, even if
    /// `SFSpeechRecognizer` decides the utterance is over — otherwise a long pause
    /// would cut the user off mid-sentence.
    private var stopRequested = false

    /// Fallback for the case where `SFSpeechRecognizer` never reports `isFinal`.
    private var finalizeTimer: Timer?

    /// Hard ceiling on a single session, so lock-to-listen cannot record forever.
    private var maxDurationTimer: Timer?

    /// Recognition error codes that are expected and should not be logged.
    /// 1110 = recording stopped (follows `endAudio`), 301 = request cancelled (follows `cancel()`).
    private static let ignoredErrorCodes: Set<Int> = [1110, 301]

    init(language: AppLanguage) {
        self.language = language
        configureRecognizer(for: language)
    }

    /// Switches the recognition language.
    ///
    /// - Important: Never call this while a session is running — swapping the
    ///   recognizer out from under a live audio tap leaves the engine in an
    ///   inconsistent state. Any in-flight recording is cancelled first.
    /// - Returns: `true` if the language is supported and was applied.
    @discardableResult
    func reconfigure(for newLanguage: AppLanguage) -> Bool {
        guard SpeechManager.isSupported(newLanguage) else {
            Logger.log("Cannot switch to \(newLanguage.rawValue): locale unsupported by SFSpeechRecognizer.")
            return false
        }

        if isBusy {
            Logger.log("Language switch while recording — cancelling the current session first.")
            cancelRecording()
        }

        language = newLanguage
        configureRecognizer(for: newLanguage)
        return true
    }

    /// Whether macOS can transcribe this language at all on this Mac.
    static func isSupported(_ language: AppLanguage) -> Bool {
        let target = language.recognitionLocale.identifier
        return SFSpeechRecognizer.supportedLocales().contains { locale in
            // Match "en-US" exactly, and "en_US" / "en" style identifiers too.
            let id = locale.identifier.replacingOccurrences(of: "_", with: "-")
            return id == target || id.hasPrefix(target.prefix(2) + "-")
        }
    }

    private func configureRecognizer(for language: AppLanguage) {
        let recognizer = SFSpeechRecognizer(locale: language.recognitionLocale)
                      ?? SFSpeechRecognizer(locale: Locale.current)
        speechRecognizer = recognizer

        // Prefer on-device recognition whenever this locale's model is available.
        isOnDeviceRecognition = recognizer?.supportsOnDeviceRecognition ?? false
        Logger.log("Speech recognition configured for \(language.recognitionLocale.identifier): "
                   + (isOnDeviceRecognition ? "on-device" : "server-based (on-device model unavailable for this locale)"))
    }

    // MARK: - Permission Checks

    func requestPermissions(completion: @escaping (Bool, Bool) -> Void) {
        var speechGranted = false
        var micGranted = false
        let group = DispatchGroup()

        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechGranted = (status == .authorized)
            group.leave()
        }

        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            micGranted = granted
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.hasSpeechPermission = speechGranted
            self?.hasMicrophonePermission = micGranted
            completion(speechGranted, micGranted)
        }
    }

    // MARK: - Recording

    func startRecording() {
        guard !audioEngine.isRunning else {
            Logger.log("SpeechManager: startRecording() called but the audio engine is already running.")
            return
        }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            Logger.log("ERROR: SFSpeechRecognizer unavailable.")
            return
        }

        // Defensive: drop any task left over from a previous session.
        cancelCurrentTask()

        stopRequested = false
        lastTranscript = ""

        startRecognitionTask(with: recognizer)

        guard installAudioTap() else {
            cancelCurrentTask()
            return
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            Logger.log("Recording started.")
            startMaxDurationTimer()
        } catch {
            Logger.log("ERROR: could not start the audio engine: \(error.localizedDescription)")
            cancelCurrentTask()
        }
    }

    /// Requested by the user (key up / explicit stop).
    /// Signals the end of the audio and waits for the final transcript.
    func stopRecording() {
        guard audioEngine.isRunning else {
            Logger.log("stopRecording() ignored: audio engine not running.")
            return
        }
        Logger.log("Stop requested by user.")

        stopRequested = true
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        // Tell the recognizer no more audio is coming → triggers isFinal or error 1110.
        recognitionRequest?.endAudio()
        audioEngine.stop()
        removeTapIfNeeded()

        // Safety net: deliver anyway if the recognizer does not answer in time.
        resetFinalizeTimer(delay: 2.0)
    }

    /// Aborts the session immediately without delivering any transcript.
    func cancelRecording() {
        Logger.log("Recording CANCELLED.")
        stopRequested = false
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        lastTranscript = ""
        cancelCurrentTask()
    }

    // MARK: - Recognition Session

    /// Restarts only the recognition task, leaving the audio engine running.
    ///
    /// Used when `SFSpeechRecognizer` ends the session by itself after a long
    /// pause but the user is still holding the hotkey.
    private func restartRecognitionSession() {
        guard audioEngine.isRunning, !stopRequested else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        Logger.log("Restarting SFSpeech recognition session (audio engine still active).")

        recognitionTask?.cancel()
        recognitionTask = nil

        startRecognitionTask(with: recognizer)

        // The existing tap still appends to the old request, so reinstall it
        // to pick up the new one.
        _ = installAudioTap()
    }

    /// Creates a fresh recognition request and task wired to the shared result handler.
    private func startRecognitionTask(with recognizer: SFSpeechRecognizer) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = isOnDeviceRecognition
        recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.lastTranscript = text

                DispatchQueue.main.async {
                    self.onPartialTranscript?(text)
                }

                if result.isFinal {
                    // Only deliver when the user asked to stop. Otherwise SFSpeech has
                    // closed the session on its own (long pause) and we resume quietly.
                    if self.stopRequested {
                        self.deliverFinalTranscript()
                    } else {
                        Logger.log("isFinal received without a stop request → restarting session.")
                        self.restartRecognitionSession()
                    }
                }
            }

            if let error {
                let code = (error as NSError).code
                let isExpected = SpeechManager.ignoredErrorCodes.contains(code)

                if !isExpected {
                    Logger.log("Recognition error: \(error.localizedDescription) (code: \(code))")

                    // A genuine failure after a stop request: deliver whatever we have.
                    if self.stopRequested {
                        self.deliverFinalTranscript()
                    }
                }
            }
        }
    }

    /// Installs the microphone tap, replacing any existing one so it always feeds
    /// the current `recognitionRequest`. Returns false if the input device is not ready.
    @discardableResult
    private func installAudioTap() -> Bool {
        let inputNode = audioEngine.inputNode
        removeTapIfNeeded()

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            Logger.log("ERROR: invalid microphone sample rate (0). Device not ready.")
            return false
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Root-mean-square of the buffer drives the equaliser bars.
            guard let channelData = buffer.floatChannelData?[0] else { return }
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(buffer.frameLength))
            let normalized = min(1.0, rms * 8)
            DispatchQueue.main.async {
                self?.onAudioLevel?(normalized)
            }
        }
        tapInstalled = true
        return true
    }

    // MARK: - Timers

    private func resetFinalizeTimer(delay: TimeInterval) {
        finalizeTimer?.invalidate()
        finalizeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            Logger.log("Finalize timer fired.")
            self.deliverFinalTranscript()
        }
    }

    /// Caps a single session at 55s so lock-to-listen cannot record indefinitely.
    private func startMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: 55.0, repeats: false) { [weak self] _ in
            guard let self, self.audioEngine.isRunning else { return }
            Logger.log("Maximum duration reached (55s). Stopping automatically.")
            self.stopRecording()
        }
    }

    // MARK: - Delivery

    private func deliverFinalTranscript() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        let text = lastTranscript
        lastTranscript = ""
        stopRequested = false
        cancelCurrentTask()

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.log("Empty transcript, reporting silence.")
            DispatchQueue.main.async { [weak self] in
                self?.onSilence?()
            }
            return
        }

        Logger.logSensitive("Final transcript delivered", text)
        DispatchQueue.main.async { [weak self] in
            self?.onFinalTranscript?(text)
        }
    }

    // MARK: - Teardown

    private func removeTapIfNeeded() {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func cancelCurrentTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeTapIfNeeded()
    }
}
