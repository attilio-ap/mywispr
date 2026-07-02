import Foundation
import Cocoa
import Combine
import SwiftUI
import Speech
import AVFoundation

/// Preset AI di trascrizione.
enum AIPreset: String, CaseIterable, Codable {
    case standard = "standard"
    case professional = "professional"
    case bullets = "bullets"
    case englishTranslation = "englishTranslation"
    case promptBuilder = "promptBuilder"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .standard: return "Standard (Correzione)"
        case .professional: return "Formale / Email"
        case .bullets: return "Elenco Puntato"
        case .englishTranslation: return "Traduttore Inglese"
        case .promptBuilder: return "Generatore di Prompt AI"
        case .custom: return "Personalizzato"
        }
    }
}

/// Modalità di visualizzazione dell'overlay a schermo (Dynamic Island)
enum OverlayMode: String, Codable {
    case idle          // Notch microscopica 1cm x 0.5cm
    case hovered       // Espansa con controlli dei Preset
    case recording     // Equalizzatore durante l'ascolto
    case processing    // Animazione di elaborazione AI
}

final class AppState: ObservableObject {
    // MARK: - Stato UI
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var isRecordingHotkey: Bool = false
    @Published var hotkeyRejectionMessage: String? = nil
    @Published var hotkeyKeyCode: CGKeyCode = 61 // Right Option di default
    @Published var audioLevel: Float = 0
    @Published var ollamaModelName: String = "qwen2.5:14b"
    @Published var transcriptionHistory: [TranscriptionRecord] = []
    @Published var totalWords: Int = 0
    @Published var timeSavedSeconds: Double = 0.0
    
    // Modalità della notch sovrimpressa
    @Published var overlayMode: OverlayMode = .idle

    // MARK: - Nuovi Stati UX Raffinati
    @Published var partialTranscript: String = ""
    @Published var processingStatusText: String = "Elaborazione..."
    @Published var showOfflineAlert: Bool = false

    // MARK: - Permessi
    @Published var hasSpeechPermission: Bool = false
    @Published var hasMicrophonePermission: Bool = false
    @Published var hasAccessibilityPermission: Bool = false

    // MARK: - Nuove impostazioni AI & Ollama
    @Published var isOllamaConnected: Bool = false
    @Published var availableOllamaModels: [String] = []
    @Published var aiPreset: AIPreset = .standard
    @Published var temperature: Double = 0.1
    @Published var customPrompt: String = ""
    @Published var glossary: [String: String] = [
        "tulle": "tool",
        "gittab": "GitHub",
        "svift": "Swift",
        "notc": "notch",
        "bild": "build",
        "opscion": "option"
    ]

    private var permissionPollTimer: Timer?

    init() {
        loadPersistedData()
        self.hasAccessibilityPermission = AXIsProcessTrusted()
        startPermissionPolling()
    }

    deinit {
        permissionPollTimer?.invalidate()
    }

    // Polling dei permessi per rendere l'interfaccia reattiva in tempo reale
    func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
            let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            let ax = AXIsProcessTrusted()
            
            if speech != self.hasSpeechPermission || mic != self.hasMicrophonePermission || ax != self.hasAccessibilityPermission {
                DispatchQueue.main.async {
                    self.hasSpeechPermission = speech
                    self.hasMicrophonePermission = mic
                    self.hasAccessibilityPermission = ax
                }
            }
        }
    }

    func triggerOfflineAlert() {
        showOfflineAlert = true
        NSSound.beep()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.showOfflineAlert = false
        }
    }

    func addRecord(_ record: TranscriptionRecord) {
        transcriptionHistory.insert(record, at: 0)
        totalWords += record.wordCount
        timeSavedSeconds += Double(record.wordCount) * 1.25 // Risparmio stimato aumentato leggermente per precisione
        persistData()
    }

    func clearHistory() {
        transcriptionHistory.removeAll()
        totalWords = 0
        timeSavedSeconds = 0.0
        persistData()
    }

    // MARK: - Gestione Glossario
    func addGlossaryItem(word: String, replacement: String) {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanWord.isEmpty && !cleanReplacement.isEmpty else { return }
        glossary[cleanWord] = cleanReplacement
        persistData()
    }

    func removeGlossaryItem(word: String) {
        glossary.removeValue(forKey: word.lowercased())
        persistData()
    }

    /// Applica le sostituzioni del glossario su un testo grezzo prima di passarlo all'AI
    func applyGlossary(to text: String) -> String {
        var processedText = text
        // Ordina le chiavi per lunghezza decrescente per evitare sovrascritture parziali
        let sortedWords = glossary.keys.sorted { $0.count > $1.count }
        
        for word in sortedWords {
            guard let replacement = glossary[word] else { continue }
            // Sostituzione case-insensitive rispettando i confini delle parole (usando espressioni regolari se possibile)
            let escapedWord = NSRegularExpression.escapedPattern(for: word)
            let pattern = "\\b\(escapedWord)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: processedText.utf16.count)
                processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: replacement)
            } else {
                // Fallback semplice
                processedText = processedText.replacingOccurrences(of: word, with: replacement, options: [.caseInsensitive])
            }
        }
        return processedText
    }

    // MARK: - Persistence
    private func persistData() {
        if let encoded = try? JSONEncoder().encode(transcriptionHistory) {
            UserDefaults.standard.set(encoded, forKey: "mw_history")
        }
        UserDefaults.standard.set(totalWords, forKey: "mw_words")
        UserDefaults.standard.set(timeSavedSeconds, forKey: "mw_time")
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "mw_hotkey")
        UserDefaults.standard.set(ollamaModelName, forKey: "mw_model_name")
        UserDefaults.standard.set(temperature, forKey: "mw_temp")
        UserDefaults.standard.set(customPrompt, forKey: "mw_custom_prompt")
        
        if let presetData = try? JSONEncoder().encode(aiPreset) {
            UserDefaults.standard.set(presetData, forKey: "mw_preset")
        }
        if let glossaryData = try? JSONEncoder().encode(glossary) {
            UserDefaults.standard.set(glossaryData, forKey: "mw_glossary")
        }
        UserDefaults.standard.synchronize()
    }

    private func loadPersistedData() {
        if let data = UserDefaults.standard.data(forKey: "mw_history"),
           let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) {
            self.transcriptionHistory = decoded
        }
        totalWords = UserDefaults.standard.integer(forKey: "mw_words")
        timeSavedSeconds = UserDefaults.standard.double(forKey: "mw_time")
        
        let savedKey = UserDefaults.standard.integer(forKey: "mw_hotkey")
        if savedKey > 0 {
            hotkeyKeyCode = CGKeyCode(savedKey)
        }
        
        if let savedModel = UserDefaults.standard.string(forKey: "mw_model_name") {
            ollamaModelName = savedModel
        }
        
        let savedTemp = UserDefaults.standard.double(forKey: "mw_temp")
        if savedTemp > 0 {
            temperature = savedTemp
        } else {
            temperature = 0.1
        }
        
        if let savedPrompt = UserDefaults.standard.string(forKey: "mw_custom_prompt") {
            customPrompt = savedPrompt
        }
        
        if let presetData = UserDefaults.standard.data(forKey: "mw_preset"),
           let decodedPreset = try? JSONDecoder().decode(AIPreset.self, from: presetData) {
            aiPreset = decodedPreset
        }
        
        if let glossaryData = UserDefaults.standard.data(forKey: "mw_glossary"),
           let decodedGlossary = try? JSONDecoder().decode([String: String].self, from: glossaryData) {
            glossary = decodedGlossary
        }
    }

    func persistHotkey() {
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "mw_hotkey")
    }
}

// MARK: - Data Model

struct TranscriptionRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let rawText: String
    let cleanedText: String

    var wordCount: Int {
        cleanedText.split(separator: " ").count
    }

    init(rawText: String, cleanedText: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.rawText = rawText
        self.cleanedText = cleanedText
    }
}
