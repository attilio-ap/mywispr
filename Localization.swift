import Foundation
import CoreGraphics

/// The languages MyWispr supports.
///
/// A single value drives both the dictation language (recognition locale, AI
/// prompt language, glossary defaults) and the interface language. `AppState`
/// stores the two separately so they can be decoupled later without a refactor.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case italian = "it"
    case english = "en"

    var id: String { rawValue }

    /// Name of the language, always written in that language.
    var displayName: String {
        switch self {
        case .italian: return "Italiano"
        case .english: return "English"
        }
    }

    var flag: String {
        switch self {
        case .italian: return "🇮🇹"
        case .english: return "🇬🇧"
        }
    }

    /// Locale handed to `SFSpeechRecognizer`.
    var recognitionLocale: Locale {
        switch self {
        case .italian: return Locale(identifier: "it-IT")
        case .english: return Locale(identifier: "en-US")
        }
    }

    /// Locale used for dates and numbers in the dashboard.
    var formattingLocale: Locale { recognitionLocale }

    /// The language the `translation` preset targets — always the other one.
    var translationTarget: AppLanguage {
        self == .italian ? .english : .italian
    }

    /// Default glossary for this language.
    ///
    /// These are phonetic fix-ups for terms the speech recogniser reliably gets
    /// wrong, and they are necessarily language-specific: an Italian speaker
    /// dictating English technical terms fails differently from an English one.
    var defaultGlossary: [String: String] {
        switch self {
        case .italian:
            return [
                "tulle": "tool",
                "gittab": "GitHub",
                "svift": "Swift",
                "notc": "notch",
                "bild": "build",
                "opscion": "option"
            ]
        case .english:
            return [
                "get hub": "GitHub",
                "my sequel": "MySQL",
                "post gress": "PostgreSQL",
                "pie torch": "PyTorch",
                "node jay ess": "Node.js",
                "dee bug": "debug"
            ]
        }
    }
}

/// Every user-facing string in the app, in both languages.
///
/// This is a plain Swift table rather than `NSLocalizedString` on purpose.
/// `NSLocalizedString` resolves against the bundle language at launch, so an
/// in-app toggle would need bundle swizzling. A struct rebuilt from
/// `@Published var uiLanguage` re-renders every SwiftUI `Text` for free, and a
/// missing string is a compile error instead of a silent fallback.
///
/// The only strings this cannot cover are the `Info.plist` usage descriptions,
/// which macOS reads from `.lproj/InfoPlist.strings` and resolves against the
/// *system* language. See `en.lproj/` and `it.lproj/`.
struct L10n {
    let language: AppLanguage

    init(_ language: AppLanguage) {
        self.language = language
    }

    /// Picks the Italian or English variant.
    private func t(_ it: String, _ en: String) -> String {
        language == .italian ? it : en
    }

    // MARK: - Menu Bar & Windows

    var menuQuitApp: String     { t("Esci da MyWispr", "Quit MyWispr") }
    var menuCut: String         { t("Taglia", "Cut") }
    var menuCopy: String        { t("Copia", "Copy") }
    var menuPaste: String       { t("Incolla", "Paste") }
    var menuSelectAll: String   { t("Seleziona Tutto", "Select All") }
    var menuOpenDashboard: String { t("Apri Dashboard", "Open Dashboard") }
    var menuQuit: String        { t("Esci", "Quit") }

    // MARK: - Overlay

    var overlayProcessing: String    { t("Elaborazione...", "Processing…") }
    var overlayStartingModel: String { t("Avvio modello AI...", "Starting AI model…") }
    var overlayOllamaOffline: String { t("Ollama Offline - Testo Grezzo", "Ollama Offline - Raw Text") }

    // MARK: - AI Presets

    func presetName(_ preset: AIPreset) -> String {
        switch preset {
        case .standard:     return t("Standard (Correzione)", "Standard (Cleanup)")
        case .professional: return t("Formale / Email", "Formal / Email")
        case .bullets:      return t("Elenco Puntato", "Bullet List")
        case .translation:  return t("Traduttore Inglese", "Italian Translator")
        case .promptBuilder: return t("Generatore di Prompt AI", "AI Prompt Builder")
        case .custom:       return t("Personalizzato", "Custom")
        }
    }

    // MARK: - Sidebar

    var sidebarHistory: String   { t("Cronologia", "History") }
    var sidebarPresets: String   { t("Personalizza Preset", "Customise Presets") }
    var sidebarSettings: String  { t("Impostazioni AI", "AI Settings") }
    var sidebarGlossary: String  { t("Glossario Tecnico", "Technical Glossary") }
    var sidebarAnalytics: String { t("Statistiche & Analytics", "Statistics & Analytics") }
    var sidebarMonitor: String   { t("Monitor Ollama", "Ollama Monitor") }
    var sidebarOllamaConnected: String { t("Ollama Connesso", "Ollama Connected") }
    var sidebarOllamaOffline: String   { t("Ollama Offline", "Ollama Offline") }
    func sidebarVersion(_ v: String) -> String { t("Versione \(v)", "Version \(v)") }

    // MARK: - Tab Titles

    var tabTitleHistory: String   { t("CRONOLOGIA E EDITOR", "HISTORY & EDITOR") }
    var tabTitlePresets: String   { t("GESTIONE PRESET AI", "AI PRESET MANAGEMENT") }
    var tabTitleSettings: String  { t("IMPOSTAZIONI AI & MODELLI", "AI SETTINGS & MODELS") }
    var tabTitleGlossary: String  { t("GLOSSARIO REGOLE", "GLOSSARY RULES") }
    var tabTitleAnalytics: String { t("STATISTICHE & ANALYTICS", "STATISTICS & ANALYTICS") }
    var tabTitleMonitor: String   { t("LIVE MONITOR OLLAMA", "OLLAMA LIVE MONITOR") }

    // MARK: - History Tab

    var historySearchPlaceholder: String { t("Cerca nello storico...", "Search history…") }
    var historyNoRecords: String   { t("Nessun record trovato", "No records found") }
    func historyWordCount(_ n: Int) -> String { t("\(n) parole", "\(n) words") }
    var historyRecordDetails: String { t("Dettagli Registrazione", "Recording Details") }
    var historyAt: String          { t("alle", "at") }
    var historyRawSpeech: String   { t("🔈 PARLATO GREZZO", "🔈 RAW SPEECH") }
    var historySilenceDetected: String { t("(Silenzio rilevato)", "(Silence detected)") }
    var historyEditedText: String  { t("✨ EDIT TESTO CORRETTO (AI)", "✨ EDIT CORRECTED TEXT (AI)") }
    var historySaveChanges: String { t("SALVA MODIFICHE", "SAVE CHANGES") }
    var historyCopyClipboard: String { t("COPIA NEGLI APPUNTI", "COPY TO CLIPBOARD") }
    var historyReprocess: String   { t("🔄 RI-ELABORA CON ALTRO PRESET", "🔄 REPROCESS WITH ANOTHER PRESET") }
    var historyProcessing: String  { t("ELABORAZIONE...", "PROCESSING…") }
    var historyApplyPreset: String { t("APPLICA PRESET", "APPLY PRESET") }
    var historyEmptySelection: String {
        t("Seleziona una trascrizione per visualizzare o modificarne il testo.",
          "Select a transcription to view or edit its text.")
    }

    // MARK: - Presets Tab

    var presetsYourCustom: String { t("I TUOI PRESET PERSONALIZZATI", "YOUR CUSTOM PRESETS") }
    var presetsEmpty: String {
        t("Nessun preset personalizzato creato. Puoi definirne uno sotto.",
          "No custom presets yet. You can define one below.")
    }
    func presetsTemp(_ v: Double) -> String { String(format: t("Temp: %.1f", "Temp: %.1f"), v) }
    var presetsActivate: String   { t("ATTIVA", "ACTIVATE") }
    var presetsCreateNew: String  { t("CREA UN NUOVO PRESET", "CREATE A NEW PRESET") }
    var presetsNamePlaceholder: String { t("Nome Preset (es. E-Mail Formale)", "Preset name (e.g. Formal Email)") }
    var presetsIconLabel: String  { t("Icona:", "Icon:") }
    var presetsPromptLabel: String {
        t("Prompt di elaborazione (Istruzioni fornite al modello LLM):",
          "Processing prompt (instructions given to the LLM):")
    }
    func presetsAITemp(_ v: Double) -> String { String(format: t("Temp AI: %.1f", "AI temp: %.1f"), v) }
    var presetsSave: String { t("SALVA PRESET", "SAVE PRESET") }

    // MARK: - Settings Tab

    var settingsHotkeySection: String { t("TASTO DI ATTIVAZIONE (HOTKEY)", "ACTIVATION KEY (HOTKEY)") }
    var settingsPressAKey: String     { t("PREMI UN TASTO...", "PRESS A KEY…") }
    var settingsHoldToTalk: String {
        t("Dettatura classica: Tieni premuto per parlare, rilascia per incollare.",
          "Classic dictation: hold to speak, release to paste.")
    }
    var settingsLockToListen: String {
        t("Ascolto Continuo: Premi due volte per registrare a mani libere. Clicca col mouse o premi nuovamente l'hotkey per interrompere.",
          "Continuous listening: press twice for hands-free recording. Click the mouse or press the hotkey again to stop.")
    }

    var settingsModelSection: String  { t("MODELLO LOCALE OLLAMA", "LOCAL OLLAMA MODEL") }
    var settingsNoModelDetected: String {
        t("⚠️ Nessun modello rilevato su Ollama localmente.",
          "⚠️ No model detected on the local Ollama.")
    }
    var settingsNoModelHint: String {
        t("Verifica che Ollama sia avviato. Puoi scaricare un modello dal tab 'Monitor Ollama'.",
          "Check that Ollama is running. You can download one from the 'Ollama Monitor' tab.")
    }
    var settingsManualModel: String { t("Inserisci nome modello a mano", "Enter model name manually") }
    var settingsActiveModel: String { t("Modello attivo:", "Active model:") }
    func settingsTemperature(_ v: Double) -> String {
        String(format: t("Temperatura AI: %.1f", "AI temperature: %.1f"), v)
    }
    var settingsTempLiteral: String  { t("Correzione Letterale", "Literal correction") }
    var settingsTempCreative: String { t("Creativo", "Creative") }
    var settingsTempBalanced: String { t("Bilanciato", "Balanced") }
    var settingsBasePresets: String  { t("PRESET DI BASE AI", "BUILT-IN AI PRESETS") }
    var settingsActivePreset: String { t("Preset standard attivo:", "Active standard preset:") }

    // MARK: - Language Section

    var languageSection: String { t("LINGUA", "LANGUAGE") }
    var languageLabel: String   { t("Lingua di dettatura e interfaccia:", "Dictation and interface language:") }
    var languageHint: String {
        t("Cambia la lingua riconosciuta dal microfono, i prompt inviati all'AI e i testi dell'interfaccia.",
          "Changes the language recognised from the microphone, the prompts sent to the AI and the interface text.")
    }
    var languageBusyWarning: String {
        t("Interrompi la registrazione in corso prima di cambiare lingua.",
          "Stop the current recording before changing language.")
    }
    var languageUnsupported: String {
        t("⚠️ Questa lingua non è disponibile per il riconoscimento vocale su questo Mac.",
          "⚠️ This language is not available for speech recognition on this Mac.")
    }

    // MARK: - Privacy Section

    var privacySection: String { t("PRIVACY E DIAGNOSTICA", "PRIVACY & DIAGNOSTICS") }
    var privacyOnDevice: String {
        t("Trascrizione on-device: l'audio non lascia il Mac.",
          "On-device transcription: audio never leaves your Mac.")
    }
    var privacyServerBased: String {
        t("Trascrizione via server Apple: il modello offline non è installato per questa lingua.",
          "Server-based transcription: the offline model is not installed for this language.")
    }
    var privacyServerHint: String {
        t("Installa la lingua in Impostazioni di Sistema > Generali > Lingua e Zona per la dettatura offline.",
          "Install the language in System Settings > General > Language & Region for offline dictation.")
    }
    var privacyLocalAI: String {
        t("Elaborazione AI sempre locale: nessun testo lascia il Mac (Ollama su 127.0.0.1).",
          "AI processing is always local: no text leaves your Mac (Ollama on 127.0.0.1).")
    }
    var privacyVerboseToggle: String {
        t("Log dettagliato (include il testo dettato)",
          "Verbose log (includes dictated text)")
    }
    var privacyVerboseHint: String {
        t("Disattivato, il log registra solo la lunghezza del testo. Attivalo solo per diagnosticare un problema.",
          "When off, the log records only the text length. Enable it only to diagnose a problem.")
    }
    var privacyClearLog: String { t("SVUOTA LOG", "CLEAR LOG") }

    // MARK: - Permissions

    var permMicrophone: String    { t("Microfono", "Microphone") }
    var permSpeech: String        { t("Riconoscimento Vocale", "Speech Recognition") }
    var permAccessibility: String { t("Accessibilità", "Accessibility") }

    // MARK: - Glossary Tab

    var glossaryAddRule: String { t("AGGIUNGI REGOLA DI SOSTITUZIONE", "ADD SUBSTITUTION RULE") }
    /// The example is language-specific: it must show a plausible mis-transcription.
    var glossaryRawPlaceholder: String { t("Voce grezza (es. svift)", "Raw entry (e.g. get hub)") }
    var glossaryReplacementPlaceholder: String {
        t("Sostituzione corretta (es. Swift)", "Correct replacement (e.g. GitHub)")
    }
    var glossaryAdd: String { t("AGGIUNGI", "ADD") }
    func glossaryActiveRules(_ n: Int) -> String { t("REGOLE ATTIVE (\(n))", "ACTIVE RULES (\(n))") }
    var glossarySearchPlaceholder: String { t("Cerca nel glossario...", "Search the glossary…") }
    var glossaryEmpty: String { t("Nessuna regola nel glossario.", "No rules in the glossary.") }

    // MARK: - Analytics Tab

    var analyticsWordsDictated: String  { t("PAROLE DETTATE", "WORDS DICTATED") }
    var analyticsWordsSubtitle: String  { t("Produttività vocale", "Voice productivity") }
    var analyticsTimeSaved: String      { t("TEMPO RISPARMIATO", "TIME SAVED") }
    var analyticsTimeSubtitle: String   { t("Velocità media stimata", "Estimated average speed") }
    var analyticsEffectiveness: String  { t("EFFICACIA", "EFFECTIVENESS") }
    var analyticsEffectivenessSubtitle: String { t("Rispetto a tastiera manuale", "Compared to manual typing") }
    var analyticsChartTitle: String {
        t("PAROLE DETTATE NEGLI ULTIMI 7 GIORNI", "WORDS DICTATED IN THE LAST 7 DAYS")
    }
    var analyticsChartEmpty: String {
        t("Dati insufficienti per generare il grafico. Inizia a dettare testo!",
          "Not enough data to draw the chart. Start dictating!")
    }
    var analyticsAxisDay: String   { t("Giorno", "Day") }
    var analyticsAxisWords: String { t("Parole", "Words") }
    var analyticsDetailed: String  { t("STATISTICHE DETTAGLIATE", "DETAILED STATISTICS") }
    var analyticsTotalTranscriptions: String { t("Trascrizioni totali effettuate", "Total transcriptions") }
    var analyticsAverageLength: String { t("Lunghezza media trascrizione", "Average transcription length") }
    func analyticsWordsValue(_ v: Double) -> String { String(format: t("%.1f parole", "%.1f words"), v) }
    var analyticsPreferredModel: String { t("Modello LLM locale preferito", "Preferred local LLM model") }

    // MARK: - Ollama Monitor Tab

    var monitorRunningModels: String {
        t("MODELLI ATTUALMENTE IN ESECUZIONE NELLA RAM/VRAM", "MODELS CURRENTLY RUNNING IN RAM/VRAM")
    }
    var monitorRefresh: String    { t("AGGIORNA", "REFRESH") }
    var monitorNotConnected: String { t("Connessione a Ollama non stabilita.", "No connection to Ollama.") }
    var monitorNoneLoaded: String {
        t("Nessun modello caricato in memoria in questo istante.", "No model loaded in memory right now.")
    }
    var monitorInMemory: String   { t("In memoria", "In memory") }
    var monitorInstalled: String  { t("MODELLI INSTALLATI LOCALMENTE", "MODELS INSTALLED LOCALLY") }
    var monitorNoneInstalled: String { t("Nessun modello installato rilevato.", "No installed model detected.") }
    var monitorInUse: String      { t("IN USO", "IN USE") }
    var monitorDownloadSection: String {
        t("SCARICA NUOVO MODELLO DA OLLAMA REGISTRY", "DOWNLOAD A NEW MODEL FROM THE OLLAMA REGISTRY")
    }
    var monitorDownloadHint: String {
        t("Inserisci il nome esatto del modello da scaricare (es: qwen2.5:7b, qwen2.5:3b, llama3).",
          "Enter the exact name of the model to download (e.g. qwen2.5:7b, qwen2.5:3b, llama3).")
    }
    var monitorDownloadPlaceholder: String { t("Esempio: qwen2.5:7b", "Example: qwen2.5:7b") }
    var monitorDownloading: String { t("SCARICAMENTO...", "DOWNLOADING…") }
    var monitorDownload: String    { t("SCARICA MODELLO", "DOWNLOAD MODEL") }

    // MARK: - Ollama Status Messages

    var ollamaOfflineCannotPull: String {
        t("Impossibile scaricare: Ollama offline.", "Cannot download: Ollama is offline.")
    }
    func ollamaPullStarted(_ model: String) -> String {
        t("Inizio download per \(model)... potrebbe richiedere tempo.",
          "Starting download for \(model)… this may take a while.")
    }
    var ollamaInvalidURL: String       { t("URL non valido.", "Invalid URL.") }
    var ollamaSerializationError: String { t("Errore di serializzazione.", "Serialization error.") }
    func ollamaDownloadError(_ msg: String) -> String {
        t("Errore durante il download: \(msg)", "Download error: \(msg)")
    }
    var ollamaModelNotFound: String {
        t("Errore: Modello non trovato o server in errore.", "Error: model not found or server error.")
    }
    func ollamaPullSuccess(_ model: String) -> String {
        t("Modello \(model) scaricato con successo!", "Model \(model) downloaded successfully!")
    }

    // MARK: - Onboarding

    var onboardingWelcome: String { t("Benvenuto in MyWispr", "Welcome to MyWispr") }
    var onboardingIntro: String {
        t("Per iniziare ad utilizzare la dettatura vocale locale intelligente, configura i permessi richiesti dal sistema operativo.",
          "To start using intelligent local voice dictation, grant the permissions the operating system requires.")
    }
    var onboardingMicTitle: String { t("Accesso al Microfono", "Microphone Access") }
    var onboardingMicDesc: String {
        t("Necessario per catturare la tua voce durante la dettatura.",
          "Required to capture your voice while dictating.")
    }
    var onboardingSpeechTitle: String { t("Riconoscimento Vocale", "Speech Recognition") }
    var onboardingSpeechDesc: String {
        t("Abilita macOS a trascrivere il parlato in testo.",
          "Lets macOS transcribe speech into text.")
    }
    var onboardingAxTitle: String { t("Accesso all'Accessibilità", "Accessibility Access") }
    var onboardingAxDesc: String {
        t("Apri le Impostazioni di Sistema per abilitare MyWispr nella sezione Accessibilità.",
          "Open System Settings to enable MyWispr under Accessibility.")
    }
    var onboardingProceed: String { t("PROCEDI ALLA DASHBOARD", "CONTINUE TO THE DASHBOARD") }
    var onboardingEnableAll: String {
        t("⚠️ Abilita tutte le autorizzazioni sopra indicate per procedere.",
          "⚠️ Grant all the permissions above to continue.")
    }
    var onboardingRestartNote: String {
        t("Nota: Su macOS, l'abilitazione dell'Accessibilità richiede a volte il riavvio manuale dell'app per avere effetto.",
          "Note: on macOS, enabling Accessibility sometimes requires manually relaunching the app to take effect.")
    }
    var onboardingRelaunch: String { t("VERIFICA E RIAVVIA APP", "VERIFY & RELAUNCH APP") }
    var onboardingGranted: String  { t("CONCESSO", "GRANTED") }
    var onboardingGrant: String    { t("CONCEDI", "GRANT") }

    // MARK: - Hotkey

    var hotkeyFnRejected: String {
        t("Il tasto Fn/Globe non è supportato da macOS come hotkey. Scegli un altro tasto (es. Option, Ctrl, Shift).",
          "macOS does not support the Fn/Globe key as a hotkey. Choose another key (e.g. Option, Ctrl, Shift).")
    }

    /// Human-readable name for a virtual key code.
    func keyName(for code: CGKeyCode) -> String {
        switch code {
        case 61:  return t("Option Destro", "Right Option")
        case 58:  return t("Option Sinistro", "Left Option")
        case 54:  return t("Command Destro", "Right Command")
        case 55:  return t("Command Sinistro", "Left Command")
        case 59:  return t("Ctrl Sinistro", "Left Ctrl")
        case 62:  return t("Ctrl Destro", "Right Ctrl")
        case 56:  return t("Shift Sinistro", "Left Shift")
        case 60:  return t("Shift Destro", "Right Shift")
        case 57:  return t("Caps Lock", "Caps Lock")
        case 36:  return t("Invio", "Return")
        case 49:  return t("Spazio", "Space")
        case 53:  return t("Esc", "Esc")
        case 48:  return t("Tab", "Tab")
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
        default:  return t("Tasto [\(code)]", "Key [\(code)]")
        }
    }
}
