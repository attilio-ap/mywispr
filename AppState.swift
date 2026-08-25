import Foundation
import Cocoa
import Combine
import SwiftUI
import Speech
import AVFoundation

/// Built-in AI post-processing presets.
///
/// Display names live in `L10n.presetName(_:)` so they follow the UI language.
enum AIPreset: String, CaseIterable, Codable {
    case standard = "standard"
    case professional = "professional"
    case bullets = "bullets"
    /// Translates into the *other* language, so it stays meaningful in both.
    /// The raw value is kept as `englishTranslation` for backwards compatibility
    /// with settings persisted before the preset became directional.
    case translation = "englishTranslation"
    case promptBuilder = "promptBuilder"
    case custom = "custom"
}

/// Display state of the on-screen overlay (the "Dynamic Island" notch).
enum OverlayMode: String, Codable {
    case idle          // Thin resting line
    case hovered       // Expanded, showing preset controls
    case recording     // Equaliser / live transcript while listening
    case processing    // AI processing animation
}

/// Single observable source of truth shared by the overlay, the dashboard and the managers.
final class AppState: ObservableObject {

    // MARK: - UI State
    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var isRecordingHotkey: Bool = false
    @Published var hotkeyRejectionMessage: String? = nil
    @Published var hotkeyKeyCode: CGKeyCode = 61 // Right Option by default
    @Published var audioLevel: Float = 0
    @Published var ollamaModelName: String = "qwen2.5:14b"
    @Published var transcriptionHistory: [TranscriptionRecord] = []
    @Published var totalWords: Int = 0
    @Published var timeSavedSeconds: Double = 0.0

    /// Current mode of the overlay notch.
    @Published var overlayMode: OverlayMode = .idle

    // MARK: - Transient UX State
    @Published var partialTranscript: String = ""
    @Published var processingStatusText: String = "Elaborazione..."
    @Published var showOfflineAlert: Bool = false

    // MARK: - Permissions
    @Published var hasSpeechPermission: Bool = false
    @Published var hasMicrophonePermission: Bool = false
    @Published var hasAccessibilityPermission: Bool = false

    /// True when speech recognition runs fully on-device. Set once at launch from
    /// `SpeechManager`, and surfaced in the dashboard so the privacy claim shown to
    /// the user always matches what the app is actually doing.
    @Published var isOnDeviceRecognition: Bool = false

    // MARK: - AI & Ollama Settings
    @Published var isOllamaConnected: Bool = false
    /// Models installed locally (`/api/tags`).
    @Published var availableOllamaModels: [String] = []
    /// Models currently resident in RAM/VRAM (`/api/ps`) — a subset of the above.
    @Published var loadedOllamaModels: [String] = []
    @Published var aiPreset: AIPreset = .standard
    @Published var temperature: Double = 0.1
    /// Legacy free-text custom instruction.
    ///
    /// Superseded by `customPresets` + `activeCustomPresetId`, but kept and still
    /// honoured so a setting saved before named presets existed is not lost.
    @Published var customPrompt: String = ""

    /// Which custom preset is in use while `aiPreset == .custom`.
    ///
    /// Activation stores a *reference* rather than copying the prompt text, so
    /// editing a preset takes effect immediately on the one in use, and the UI
    /// can show which is active — neither of which was possible with a copy.
    @Published var activeCustomPresetId: UUID? = nil

    @Published var customPresets: [CustomPreset] = []

    /// The active custom preset, if any.
    var activeCustomPreset: CustomPreset? {
        guard let id = activeCustomPresetId else { return nil }
        return customPresets.first { $0.id == id }
    }

    /// The instruction actually sent to the model for the `.custom` preset.
    /// Falls back to the legacy free-text prompt when no preset is selected.
    var effectiveCustomPrompt: String {
        activeCustomPreset?.systemPrompt ?? customPrompt
    }

    /// Name to show for the current preset: the custom preset's own name when one
    /// is active, so the notch reads "Slack reply" rather than "Personalizzato".
    func presetDisplayName(_ l10n: L10n) -> String {
        if aiPreset == .custom, let active = activeCustomPreset { return active.name }
        return l10n.presetName(aiPreset)
    }

    /// Writes dictated text to the diagnostic log. Off by default — see `Logger`.
    @Published var verboseLogging: Bool = false {
        didSet {
            guard verboseLogging != oldValue else { return }
            UserDefaults.standard.set(verboseLogging, forKey: Logger.verboseDefaultsKey)
        }
    }

    /// Phonetic fix-ups applied before the text reaches the AI. Seeded from
    /// `AppLanguage.defaultGlossary` and edited by the user in the Glossary tab.
    @Published var glossary: [String: String] = AppLanguage.italian.defaultGlossary

    // MARK: - Language

    /// Language spoken into the microphone. Drives the recognition locale,
    /// the AI prompts and the default glossary.
    @Published var dictationLanguage: AppLanguage = .italian

    /// Language of the interface. Kept separate from `dictationLanguage` so the
    /// two can be decoupled later; today the picker sets both together.
    @Published var uiLanguage: AppLanguage = .italian {
        didSet {
            guard uiLanguage != oldValue else { return }
            l10n = L10n(uiLanguage)
        }
    }

    /// String table for the current UI language. Republished on every change so
    /// SwiftUI re-renders the whole dashboard.
    @Published private(set) var l10n: L10n = L10n(.italian)

    // MARK: - Appearance

    /// Light / dark / follow-the-system. Applied to `NSApp` on change.
    @Published var appearance: AppAppearance = .system {
        didSet {
            guard appearance != oldValue else { return }
            appearance.apply()
            UserDefaults.standard.set(appearance.rawValue, forKey: "mw_appearance")
        }
    }

    private var permissionPollTimer: Timer?

    init() {
        loadPersistedData()
        refreshPermissions()
        startPermissionPolling()
    }

    deinit {
        permissionPollTimer?.invalidate()
    }

    // MARK: - Permissions

    func refreshPermissions() {
        let speech = SFSpeechRecognizer.authorizationStatus() == .authorized
        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let ax = AXIsProcessTrusted()

        DispatchQueue.main.async {
            if speech != self.hasSpeechPermission { self.hasSpeechPermission = speech }
            if mic != self.hasMicrophonePermission { self.hasMicrophonePermission = mic }
            if ax != self.hasAccessibilityPermission { self.hasAccessibilityPermission = ax }
        }
    }

    /// macOS sends no notification when TCC permissions change, so the UI polls
    /// to stay in sync while the user is in System Settings.
    func startPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshPermissions()
        }
    }

    // MARK: - Alerts

    func triggerOfflineAlert() {
        showOfflineAlert = true
        NSSound.beep()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.showOfflineAlert = false
        }
    }

    // MARK: - History

    /// Rough estimate: typing is ~1.25s per word slower than dictating.
    /// Shared by `addRecord` and `updateRecord` so the two cannot disagree.
    static let secondsSavedPerWord: Double = 1.25

    func addRecord(_ record: TranscriptionRecord) {
        transcriptionHistory.insert(record, at: 0)
        totalWords += record.wordCount
        timeSavedSeconds += Double(record.wordCount) * AppState.secondsSavedPerWord
        persistData()
    }

    func clearHistory() {
        transcriptionHistory.removeAll()
        totalWords = 0
        timeSavedSeconds = 0.0
        persistData()
    }

    func updateRecord(id: UUID, newCleanedText: String) {
        guard let idx = transcriptionHistory.firstIndex(where: { $0.id == id }) else { return }

        // Keep the running totals in step with the edit, otherwise Analytics
        // slowly drifts away from the history it is supposed to describe.
        let before = transcriptionHistory[idx].wordCount
        transcriptionHistory[idx].cleanedText = newCleanedText
        let delta = transcriptionHistory[idx].wordCount - before

        totalWords = max(0, totalWords + delta)
        timeSavedSeconds = max(0, timeSavedSeconds + Double(delta) * AppState.secondsSavedPerWord)
        persistData()
    }

    // MARK: - Language

    /// Switches both the dictation and interface language.
    ///
    /// Glossary entries that are still at the previous language's defaults are
    /// swapped for the new language's; anything the user added or edited is
    /// preserved, because a phonetic rule for one language is noise in the other.
    ///
    /// - Note: The caller is responsible for reconfiguring `SpeechManager` and
    ///   for refusing to call this mid-recording.
    func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != dictationLanguage || newLanguage != uiLanguage else { return }

        let oldDefaults = dictationLanguage.defaultGlossary
        var updated = glossary
        for (key, value) in oldDefaults where updated[key] == value {
            updated.removeValue(forKey: key)
        }
        for (key, value) in newLanguage.defaultGlossary where updated[key] == nil {
            updated[key] = value
        }
        glossary = updated

        dictationLanguage = newLanguage
        uiLanguage = newLanguage
        persistData()

        Logger.log("Language switched to \(newLanguage.rawValue).")
    }

    // MARK: - Glossary

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

    /// Applies the glossary substitutions to a raw transcript before it reaches the AI.
    func applyGlossary(to text: String) -> String {
        var processedText = text
        // Longest keys first, so a short key cannot clobber part of a longer match.
        let sortedWords = glossary.keys.sorted { $0.count > $1.count }

        for word in sortedWords {
            guard let replacement = glossary[word] else { continue }
            // Case-insensitive replacement respecting word boundaries.
            let escapedWord = NSRegularExpression.escapedPattern(for: word)
            let pattern = "\\b\(escapedWord)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(location: 0, length: processedText.utf16.count)
                let template = NSRegularExpression.escapedTemplate(for: replacement)
                processedText = regex.stringByReplacingMatches(in: processedText, options: [], range: range, withTemplate: template)
            } else {
                // Fallback for patterns the regex engine rejects.
                processedText = processedText.replacingOccurrences(of: word, with: replacement, options: [.caseInsensitive])
            }
        }
        return processedText
    }

    // MARK: - Custom Presets

    @discardableResult
    func addCustomPreset(name: String, icon: String, prompt: String, temp: Double) -> CustomPreset {
        let preset = CustomPreset(id: UUID(), name: name, icon: icon, systemPrompt: prompt, temperature: temp)
        customPresets.append(preset)
        persistData()
        return preset
    }

    /// Edits a preset in place.
    ///
    /// When the edited preset is the active one its temperature is applied at
    /// once; the prompt needs no copying because `effectiveCustomPrompt` reads
    /// through to the preset itself.
    func updateCustomPreset(id: UUID, name: String, icon: String, prompt: String, temp: Double) {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        customPresets[index].name = name
        customPresets[index].icon = icon
        customPresets[index].systemPrompt = prompt
        customPresets[index].temperature = temp

        if activeCustomPresetId == id {
            temperature = temp
        }
        persistData()
    }

    /// Returns to the standard preset without touching the saved presets.
    ///
    /// The temperature is deliberately left where it is: activating a preset
    /// applied its value, and silently moving the slider again on the way out
    /// would be a change the user did not ask for.
    func deactivateCustomPreset() {
        activeCustomPresetId = nil
        aiPreset = .standard
        persistData()
    }

    /// Makes a custom preset the one in use.
    func activateCustomPreset(id: UUID) {
        guard let preset = customPresets.first(where: { $0.id == id }) else { return }
        activeCustomPresetId = id
        aiPreset = .custom
        temperature = preset.temperature
        persistData()
    }

    func removeCustomPreset(id: UUID) {
        customPresets.removeAll(where: { $0.id == id })

        // Deleting the preset in use would otherwise leave `.custom` selected
        // with nothing behind it, silently sending an empty instruction.
        if activeCustomPresetId == id {
            activeCustomPresetId = nil
            if customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                aiPreset = .standard
            }
        }
        persistData()
    }

    // MARK: - Persistence

    func persistData() {
        if let encoded = try? JSONEncoder().encode(transcriptionHistory) {
            UserDefaults.standard.set(encoded, forKey: "mw_history")
        }
        UserDefaults.standard.set(totalWords, forKey: "mw_words")
        UserDefaults.standard.set(timeSavedSeconds, forKey: "mw_time")
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "mw_hotkey")
        UserDefaults.standard.set(ollamaModelName, forKey: "mw_model_name")
        UserDefaults.standard.set(temperature, forKey: "mw_temp")
        UserDefaults.standard.set(customPrompt, forKey: "mw_custom_prompt")
        if let activeId = activeCustomPresetId {
            UserDefaults.standard.set(activeId.uuidString, forKey: "mw_active_custom_preset")
        } else {
            UserDefaults.standard.removeObject(forKey: "mw_active_custom_preset")
        }
        UserDefaults.standard.set(verboseLogging, forKey: Logger.verboseDefaultsKey)
        UserDefaults.standard.set(dictationLanguage.rawValue, forKey: "mw_dictation_language")
        UserDefaults.standard.set(uiLanguage.rawValue, forKey: "mw_ui_language")
        UserDefaults.standard.set(appearance.rawValue, forKey: "mw_appearance")

        if let presetData = try? JSONEncoder().encode(aiPreset) {
            UserDefaults.standard.set(presetData, forKey: "mw_preset")
        }
        if let glossaryData = try? JSONEncoder().encode(glossary) {
            UserDefaults.standard.set(glossaryData, forKey: "mw_glossary")
        }
        if let customPresetsData = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(customPresetsData, forKey: "mw_custom_presets")
        }
    }

    func persistHotkey() {
        UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "mw_hotkey")
    }

    private func loadPersistedData() {
        if let data = UserDefaults.standard.data(forKey: "mw_history"),
           let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) {
            self.transcriptionHistory = decoded
        }
        totalWords = UserDefaults.standard.integer(forKey: "mw_words")
        timeSavedSeconds = UserDefaults.standard.double(forKey: "mw_time")
        verboseLogging = UserDefaults.standard.bool(forKey: Logger.verboseDefaultsKey)

        // Language first: the glossary default below depends on it.
        if let raw = UserDefaults.standard.string(forKey: "mw_dictation_language"),
           let lang = AppLanguage(rawValue: raw) {
            dictationLanguage = lang
        }
        if let raw = UserDefaults.standard.string(forKey: "mw_ui_language"),
           let lang = AppLanguage(rawValue: raw) {
            uiLanguage = lang
        }
        l10n = L10n(uiLanguage)
        glossary = dictationLanguage.defaultGlossary

        if let raw = UserDefaults.standard.string(forKey: "mw_appearance"),
           let a = AppAppearance(rawValue: raw) {
            appearance = a
        }

        let savedKey = UserDefaults.standard.integer(forKey: "mw_hotkey")
        if savedKey > 0 {
            hotkeyKeyCode = CGKeyCode(savedKey)
        }

        if let savedModel = UserDefaults.standard.string(forKey: "mw_model_name") {
            ollamaModelName = savedModel
        }

        // A stored 0 means "never set", so fall back to the default.
        let savedTemp = UserDefaults.standard.double(forKey: "mw_temp")
        temperature = savedTemp > 0 ? savedTemp : 0.1

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
        if let customPresetsData = UserDefaults.standard.data(forKey: "mw_custom_presets"),
           let decodedPresets = try? JSONDecoder().decode([CustomPreset].self, from: customPresetsData) {
            customPresets = decodedPresets
        }

        // Restore the active preset, ignoring a reference to one that no longer exists.
        if let raw = UserDefaults.standard.string(forKey: "mw_active_custom_preset"),
           let id = UUID(uuidString: raw),
           customPresets.contains(where: { $0.id == id }) {
            activeCustomPresetId = id
        }
    }
}

// MARK: - Notification Names

/// Cross-component signals. Declared here rather than in `main.swift` so views
/// and tools can compile without pulling in the app entry point.
extension Notification.Name {
    static let mywisprStartHotkeyRecording = Notification.Name("mywispr.startHotkeyRecording")
    static let mywisprToggleDashboard = Notification.Name("mywispr.toggleDashboard")
    static let mywisprRefreshOllama = Notification.Name("mywispr.refreshOllama")
}

// MARK: - Data Model

struct CustomPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var systemPrompt: String
    var temperature: Double
}

struct TranscriptionRecord: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let rawText: String
    var cleanedText: String

    var wordCount: Int {
        // Split on any whitespace, not just spaces: the Bullet List preset emits
        // newline-separated Markdown, which " " alone would undercount.
        cleanedText.split(whereSeparator: \.isWhitespace).count
    }

    init(rawText: String, cleanedText: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.rawText = rawText
        self.cleanedText = cleanedText
    }
}
