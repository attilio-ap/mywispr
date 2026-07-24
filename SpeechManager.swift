import Foundation
import Speech
import AVFoundation
import Accelerate

/// Gestisce la registrazione audio e la trascrizione vocale offline tramite SFSpeechRecognizer.
final class SpeechManager {

    var onFinalTranscript: ((String) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onSilence: (() -> Void)?

    // Permessi - controllati su init, aggiornati tramite callback
    private(set) var hasSpeechPermission = false
    private(set) var hasMicrophonePermission = false

    // Internals
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var lastTranscript = ""
    private var tapInstalled = false

    // Indica se il chiamante ha richiesto uno stop esplicito (keyUp).
    // Mentre questo è false, il finalizeTimer NON viene mai consegnato
    // anche se SFSpeech pensa di aver finito — evita interruzioni involontarie.
    private var stopRequested = false

    // Timer per gestire il caso in cui SFSpeechRecognizer non chiami mai isFinal=true
    private var finalizeTimer: Timer?

    // Timer di sicurezza massima: dopo 60s forziamo lo stop anche senza keyUp
    // (evita che la sessione rimanga attiva per sempre in lock-to-listen)
    private var maxDurationTimer: Timer?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "it-IT"))
                        ?? SFSpeechRecognizer(locale: Locale.current)
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
            Logger.log("SpeechManager: startRecording() chiamato ma audioEngine già in esecuzione.")
            return
        }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            Logger.log("ERRORE: SFSpeechRecognizer non disponibile.")
            return
        }

        // Annulla task precedente (difensivo)
        cancelCurrentTask()

        stopRequested = false
        lastTranscript = ""

        // Prepara la nuova richiesta
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        self.recognitionRequest = request

        // Avvia il task di riconoscimento
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.lastTranscript = text
                Logger.log("Parziale: \(text)")

                DispatchQueue.main.async {
                    self.onPartialTranscript?(text)
                }

                if result.isFinal {
                    Logger.log("SFSpeech: isFinal=true ricevuto")
                    // Consegna solo se lo stop è stato esplicitamente richiesto.
                    // Altrimenti SFSpeech può chiudere la sessione da solo (es. pausa lunga)
                    // e noi non vogliamo interrompere l'utente.
                    if self.stopRequested {
                        self.deliverFinalTranscript()
                    } else {
                        // SFSpeech ha chiuso la sessione in autonomia (pausa troppo lunga).
                        // Riavviamo silenziosamente se siamo ancora in registrazione.
                        Logger.log("isFinal ricevuto senza stopRequested → riavvio sessione di riconoscimento.")
                        self.restartRecognitionSession()
                    }
                }
            }

            if let error {
                let nsError = error as NSError
                // Errore 1110 = recording stopped (atteso dopo endAudio)
                // Errore 301 = riconoscimento cancellato (atteso dopo cancel())
                let ignoredCodes = [1110, 301]
                if !ignoredCodes.contains(nsError.code) {
                    Logger.log("Errore riconoscimento: \(error.localizedDescription) (code: \(nsError.code))")
                }

                // Se c'è un errore vero e lo stop era stato richiesto, consegna quel che abbiamo
                if self.stopRequested && !ignoredCodes.contains(nsError.code) {
                    self.deliverFinalTranscript()
                }
            }
        }

        // Installa il tap sull'audio engine
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0 else {
            Logger.log("ERRORE: Sample rate del microfono non valido (0). Dispositivo non pronto.")
            cancelCurrentTask()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = vDSP_Length(buffer.frameLength)
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, frameLength)
            let normalized = min(1.0, rms * 8)
            DispatchQueue.main.async {
                self?.onAudioLevel?(normalized)
            }
        }
        tapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
            Logger.log("Registrazione avviata.")
            startMaxDurationTimer()
        } catch {
            Logger.log("ERRORE: Impossibile avviare audioEngine: \(error.localizedDescription)")
            cancelCurrentTask()
        }
    }

    /// Richiesto dall'utente (keyUp / stop esplicito).
    /// Segnala la fine dell'audio e aspetta la trascrizione finale da SFSpeech.
    func stopRecording() {
        guard audioEngine.isRunning else {
            Logger.log("stopRecording() ignorato: audioEngine non in esecuzione.")
            return
        }
        Logger.log("Stop registrazione richiesto (utente).")

        stopRequested = true
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil

        // Segnala la fine dell'audio al recognizer → triggera isFinal o errore 1110
        recognitionRequest?.endAudio()
        audioEngine.stop()
        removeTapIfNeeded()

        // Timer di sicurezza: se SFSpeech non risponde entro 2s, consegna comunque
        resetFinalizeTimer(delay: 2.0)
    }

    /// Annulla immediatamente la registrazione senza consegnare alcuna trascrizione.
    func cancelRecording() {
        Logger.log("Registrazione ANNULLATA.")
        stopRequested = false
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        lastTranscript = ""
        cancelCurrentTask()
    }

    // MARK: - Internals

    /// Riavvia solo il task di riconoscimento (non l'audio engine).
    /// Usato quando SFSpeech chiude la sessione in autonomia per pausa lunga.
    private func restartRecognitionSession() {
        guard audioEngine.isRunning, !stopRequested else { return }
        Logger.log("Riavvio sessione di riconoscimento SFSpeech (audio engine ancora attivo).")

        // Cancella il vecchio task
        recognitionTask?.cancel()
        recognitionTask = nil

        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        // Crea nuova request mantenendo l'audio engine attivo
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        // Reinstalla il tap puntando alla nuova request
        // (il tap esistente è già installato, ma puntava alla vecchia request)
        // Rimuoviamo e reinstalliamo per aggiornare il riferimento
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        tapInstalled = false

        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = vDSP_Length(buffer.frameLength)
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, frameLength)
            let normalized = min(1.0, rms * 8)
            DispatchQueue.main.async {
                self?.onAudioLevel?(normalized)
            }
        }
        tapInstalled = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.lastTranscript = text
                DispatchQueue.main.async { self.onPartialTranscript?(text) }

                if result.isFinal {
                    if self.stopRequested {
                        self.deliverFinalTranscript()
                    } else {
                        self.restartRecognitionSession()
                    }
                }
            }

            if let error {
                let nsError = error as NSError
                let ignoredCodes = [1110, 301]
                if !ignoredCodes.contains(nsError.code) {
                    Logger.log("Errore (sessione riavviata): \(error.localizedDescription)")
                }
                if self.stopRequested && !ignoredCodes.contains(nsError.code) {
                    self.deliverFinalTranscript()
                }
            }
        }
    }

    private func resetFinalizeTimer(delay: TimeInterval) {
        finalizeTimer?.invalidate()
        finalizeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            Logger.log("Timer di finalizzazione scattato.")
            self.deliverFinalTranscript()
        }
    }

    /// Timer massima durata sessione (lock-to-listen): evita sessioni infinite
    private func startMaxDurationTimer() {
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: 55.0, repeats: false) { [weak self] _ in
            guard let self, self.audioEngine.isRunning else { return }
            Logger.log("Timer massima durata scattato (55s). Stop automatico.")
            self.stopRecording()
        }
    }

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
            Logger.log("Trascrizione vuota, segnalo silenzio.")
            DispatchQueue.main.async { [weak self] in
                self?.onSilence?()
            }
            return
        }

        Logger.log("Trascrizione finale consegnata: \(text)")
        DispatchQueue.main.async { [weak self] in
            self?.onFinalTranscript?(text)
        }
    }

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
