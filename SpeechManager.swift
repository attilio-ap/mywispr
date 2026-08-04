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
    private var tapInstalled = false

    /// Text accumulated across this user-level session.
    private var transcript = TranscriptAccumulator()

    /// Guards against delivering the same session twice.
    ///
    /// `stopRecording()` arms a 2s safety-net timer in case the recogniser never
    /// answers. If the recogniser *does* answer at roughly the same moment, both
    /// paths call `deliverFinalTranscript()`. Without this flag they can each
    /// read the transcript before either clears it, and the text gets pasted
    /// twice; the later of the two would otherwise also report a spurious
    /// silence, collapsing the overlay while Ollama was still processing.
    private var hasDelivered = false

    /// Set when the caller explicitly asks to stop (key up).
    ///
    /// While this is false a final result is never delivered, even if
    /// `SFSpeechRecognizer` decides the utterance is over — otherwise a long pause
    /// would cut the user off mid-sentence.
    private var stopRequested = false

    /// Fallback for the case where `SFSpeechRecognizer` never reports `isFinal`.
    private var finalizeTimer: Timer?

    /// Rotates the recognition task before it reaches its own internal limit.
    ///
    /// There is no cap on how long the user may speak — the audio engine runs
    /// for as long as they hold the key. But a single `SFSpeechRecognitionTask`
    /// will not run indefinitely, so one is swapped for a fresh one every
    /// `taskRotationInterval`, carrying the text across via the accumulator.
    /// The microphone is never interrupted.
    private var taskRotationTimer: Timer?

    /// Comfortably inside the limit a recognition task will tolerate.
    private static let taskRotationInterval: TimeInterval = 50

    /// Identifies the live recognition task.
    ///
    /// Cancelling a task still produces callbacks, and a task being retired
    /// during a rotation can answer with `isFinal` — which triggered a second
    /// rotation 23ms after the first, and could let a late result from a replaced
    /// task overwrite text that had already moved on. Callbacks stamped with an
    /// older generation are ignored.
    private var taskGeneration = 0

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
        hasDelivered = false
        transcript.reset()

        startRecognitionTask(with: recognizer)

        guard installAudioTap() else {
            cancelCurrentTask()
            return
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            Logger.log("Recording started.")
            startTaskRotationTimer()
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
        taskRotationTimer?.invalidate()
        taskRotationTimer = nil

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
        hasDelivered = false
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        taskRotationTimer?.invalidate()
        taskRotationTimer = nil
        transcript.reset()
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

        // Keep what has already been said: the replacement task starts its own
        // transcription from scratch and would otherwise wipe it.
        transcript.commitCurrent()
        Logger.log("Restarting SFSpeech recognition session (audio engine still active, \(transcript.committed.count) chars carried over).")

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

        // The recogniser invokes this on an arbitrary queue. Everything it
        // touches — the transcript, the task/request handles, and the Timers —
        // is owned by the main queue, and `Timer.invalidate()` is only valid on
        // the thread that scheduled it, so hop before doing any of it.
        taskGeneration += 1
        let generation = taskGeneration

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, generation == self.taskGeneration else { return }
                self.handleRecognition(result: result, error: error)
            }
        }
    }

    /// Processes one callback from the recogniser. Always on the main queue.
    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let previouslyCommitted = transcript.committed.count
            transcript.update(result.bestTranscription.formattedString)
            if transcript.committed.count != previouslyCommitted {
                Logger.log("Recogniser started a new utterance; \(transcript.committed.count) chars carried over.")
            }
            onPartialTranscript?(transcript.full)

            if result.isFinal {
                // Only deliver when the user asked to stop. Otherwise SFSpeech has
                // closed the session on its own (long pause) and we resume quietly.
                if stopRequested {
                    deliverFinalTranscript()
                } else {
                    Logger.log("isFinal received without a stop request → restarting session.")
                    restartRecognitionSession()
                }
            }
        }

        if let error {
            let code = (error as NSError).code
            guard !SpeechManager.ignoredErrorCodes.contains(code) else { return }

            Logger.log("Recognition error: \(error.localizedDescription) (code: \(code))")

            // A genuine failure after a stop request: deliver whatever we have.
            if stopRequested {
                deliverFinalTranscript()
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

    /// Keeps a long dictation alive by cycling the recognition task underneath it.
    private func startTaskRotationTimer() {
        taskRotationTimer?.invalidate()
        taskRotationTimer = Timer.scheduledTimer(
            withTimeInterval: Self.taskRotationInterval, repeats: true
        ) { [weak self] _ in
            guard let self, self.audioEngine.isRunning, !self.stopRequested else { return }
            Logger.log("Rotating the recognition task to keep a long dictation going.")
            self.restartRecognitionSession()
        }
    }

    // MARK: - Delivery

    private func deliverFinalTranscript() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !hasDelivered else {
            Logger.log("Duplicate delivery suppressed (recogniser and safety-net timer raced).")
            return
        }
        hasDelivered = true

        finalizeTimer?.invalidate()
        finalizeTimer = nil
        taskRotationTimer?.invalidate()
        taskRotationTimer = nil

        let text = transcript.full
        transcript.reset()
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

// MARK: - Transcript Accumulator

/// Accumulates recognised text across the several `SFSpeechRecognitionTask`s
/// that make up one user-level dictation session.
///
/// `SFSpeechRecognizer` finalises and ends its task whenever the speaker pauses
/// for long enough. MyWispr transparently starts a replacement task so the user
/// can keep talking — but each task reports its own transcription from scratch.
/// Without this accumulator the replacement would overwrite everything said
/// before the pause, so a pause silently reset the dictation to nothing.
struct TranscriptAccumulator {

    /// Text from tasks that have already finished in this session.
    private(set) var committed = ""

    /// Text from the task currently running.
    private(set) var current = ""

    /// Records the recogniser's latest transcription for the running task.
    ///
    /// `SFSpeechRecognizer` normally *extends* what it reports as the speaker
    /// continues: "ciao" → "ciao come" → "ciao come stai". After a pause it can
    /// silently begin a new utterance, and the string drops back to just the new
    /// words — without ever setting `isFinal`. Assigning that straight into
    /// `current` discarded everything said before the pause, which is what made
    /// a pause look like it reset the dictation.
    ///
    /// So the segment boundary is detected from the text itself. The check is
    /// deliberately conservative: the recogniser also *revises* its wording as it
    /// goes ("ciao come" → "Ciao, come"), and treating a revision as a new
    /// segment would duplicate text instead of losing it.
    mutating func update(_ transcription: String) {
        let incoming = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incoming.isEmpty else { return }

        if startsNewSegment(incoming) {
            commitCurrent()
        }
        current = incoming
    }

    /// True when the incoming text cannot be a refinement of the current one.
    ///
    /// Requires both that it does not continue the current text *and* that it is
    /// substantially shorter, so ordinary rewording is never mistaken for a reset.
    private func startsNewSegment(_ incoming: String) -> Bool {
        guard !current.isEmpty else { return false }
        if Self.strippingNoise(incoming).hasPrefix(Self.strippingNoise(current)) {
            return false        // still growing, or only punctuation changed
        }
        return incoming.count * 2 < current.count
    }

    /// Letters and digits only, lowercased: lets a comma or a capital appearing
    /// mid-stream count as the same text rather than a new utterance.
    private static func strippingNoise(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Everything recognised so far, normalised.
    ///
    /// `current` is trimmed here rather than only at the ends of the joined
    /// string: the recogniser can report leading whitespace, which would
    /// otherwise leave a double space at the seam between segments.
    var full: String {
        let cur = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if committed.isEmpty { return cur }
        if cur.isEmpty { return committed }
        return committed + " " + cur
    }

    /// Folds the finishing task's text into `committed`. Call before replacing
    /// the recognition task, otherwise its text is lost.
    mutating func commitCurrent() {
        let text = current.trimmingCharacters(in: .whitespacesAndNewlines)
        current = ""
        guard !text.isEmpty else { return }
        committed = committed.isEmpty ? text : committed + " " + text
    }

    /// Clears everything, for the start of a new session or a cancellation.
    mutating func reset() {
        committed = ""
        current = ""
    }
}
