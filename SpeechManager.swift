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

    // Timer per gestire il caso in cui SFSpeechRecognizer non chiami mai isFinal=true
    private var finalizeTimer: Timer?

    init() {
        // Usa "it-IT" ma con fallback sull'identificatore di sistema
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
            Logger.log("ERRORE: SFSpeechRecognizer non disponibile. Verifica i permessi.")
            return
        }

        // Annulla task precedente (difensivo)
        cancelCurrentTask()

        // Prepara la nuova richiesta
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Utilizziamo il riconoscimento cloud di Apple ad altissima precisione (con punteggiatura automatica)
        // anziché forzare quello locale, il quale richiede pacchetti offline spesso non installati o incompleti.
        request.requiresOnDeviceRecognition = false
        self.recognitionRequest = request
        self.lastTranscript = ""

        // Avvia il task
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.lastTranscript = text
                Logger.log("Parziale: \(text)")

                // Invia la trascrizione parziale in tempo reale sul main thread
                DispatchQueue.main.async {
                    self.onPartialTranscript?(text)
                }

                // Resetta il timer di finalizzazione ad ogni aggiornamento
                self.resetFinalizeTimer()

                if result.isFinal {
                    self.deliverFinalTranscript()
                }
            }

            if let error {
                // Ignora l'errore 1110 (kAFAssistantErrorDomain / recording stopped) che è atteso
                let nsError = error as NSError
                if nsError.code != 1110 {
                    Logger.log("Errore riconoscimento: \(error.localizedDescription)")
                }
                // Non resettare qua: aspetta deliverFinalTranscript dal timer o da isFinal
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

            // Calcola il livello audio RMS per la visualizzazione
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = vDSP_Length(buffer.frameLength)
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, frameLength)
            // Scala: voce tipica ha RMS ~0.01-0.15, normalizziamo a 0-1
            let normalized = min(1.0, rms * 8)
            DispatchQueue.main.async {
                self?.onAudioLevel?(normalized)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            Logger.log("Registrazione avviata.")
        } catch {
            Logger.log("ERRORE: Impossibile avviare audioEngine: \(error.localizedDescription)")
            cancelCurrentTask()
        }
    }

    func stopRecording() {
        guard audioEngine.isRunning else { return }
        Logger.log("Stop registrazione richiesto.")

        // Segnala la fine dell'audio al recognizer → questo triggera isFinal o l'errore 1110
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Timer di sicurezza breve: se SFSpeechRecognizer non risponde entro 0.8s
        // (click accidentale senza parole), torna in idle senza attendere.
        resetFinalizeTimer(delay: 0.8)
    }

    /// Annulla immediatamente la registrazione senza consegnare alcuna trascrizione.
    /// Usato per click accidentali: niente processing, niente incolla, torna subito a idle.
    func cancelRecording() {
        guard audioEngine.isRunning else { return }
        Logger.log("Registrazione ANNULLATA (click accidentale).")
        finalizeTimer?.invalidate()
        finalizeTimer = nil
        lastTranscript = ""
        cancelCurrentTask()
    }


    // MARK: - Internals

    private func resetFinalizeTimer(delay: TimeInterval = 2.0) {
        finalizeTimer?.invalidate()
        finalizeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, !self.lastTranscript.isEmpty else { return }
            Logger.log("Timer di finalizzazione scattato. Consegno trascrizione.")
            self.deliverFinalTranscript()
        }
    }

    private func deliverFinalTranscript() {
        finalizeTimer?.invalidate()
        finalizeTimer = nil

        let text = lastTranscript
        lastTranscript = ""
        cancelCurrentTask()

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.log("Trascrizione vuota, ignoro.")
            DispatchQueue.main.async { [weak self] in
                self?.onSilence?()
            }
            return
        }

        Logger.log("Trascrizione finale: \(text)")
        DispatchQueue.main.async { [weak self] in
            self?.onFinalTranscript?(text)
        }
    }

    private func cancelCurrentTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
