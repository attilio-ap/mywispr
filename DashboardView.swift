import SwiftUI
import Speech
import AVFoundation
import Charts

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedTab: Int = 0 // 0 = Cronologia, 1 = Preset, 2 = Impostazioni, 3 = Glossario, 4 = Analytics, 5 = Ollama Monitor
    
    // Stati per la Cronologia
    @State private var selectedRecordId: UUID? = nil
    @State private var editedCleanedText: String = ""
    @State private var selectedReprocessPreset: AIPreset = .standard
    @State private var isReprocessing: Bool = false
    @State private var searchHistoryQuery: String = ""

    // Stati per i Preset
    @State private var newPresetName: String = ""
    @State private var newPresetIcon: String = "doc.text.fill"
    @State private var newPresetPrompt: String = ""
    @State private var newPresetTemp: Double = 0.3
    @State private var showAddPresetForm: Bool = false

    // Stati per il Glossario
    @State private var newWord: String = ""
    @State private var newReplacement: String = ""
    @State private var searchGlossaryQuery: String = ""

    // Stati per Ollama Monitor
    @State private var pullModelName: String = ""
    @State private var pullStatusMessage: String = ""
    @State private var isPulling: Bool = false

    // Icone supportate per i Preset
    private let availableIcons = [
        "square.and.pencil", "doc.text.fill", "briefcase.fill", "list.bullet",
        "character.bubble.fill", "lightbulb.fill", "bolt.fill", "gear",
        "brain.head.profile", "globe", "command", "envelope.fill", "message.fill"
    ]

    var body: some View {
        ZStack {
            if !state.hasSpeechPermission || !state.hasMicrophonePermission || !state.hasAccessibilityPermission {
                onboardingView
            } else {
                mainAppView
            }
        }
        .frame(width: 820, height: 560)
        .background(Color(NSColor.windowBackgroundColor))
        .preferredColorScheme(.light)
        .background(
            VStack {
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) { EmptyView() }
                .keyboardShortcut("q", modifiers: .command)

                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("mywispr.toggleDashboard"), object: nil)
                }) { EmptyView() }
                .keyboardShortcut("d", modifiers: .command)
            }
            .opacity(0)
        )
    }

    // MARK: - Main Application View (Sidebar Layout)

    private var mainAppView: some View {
        HStack(spacing: 0) {
            // SIDEBAR
            sidebarView
                .frame(width: 200)
                .background(Color(white: 0.95))
            
            Divider().background(Color(white: 0.88))
            
            // DETAIL PANEL
            VStack(spacing: 0) {
                detailHeader
                Divider().background(Color(white: 0.9))
                
                ZStack {
                    Color(white: 0.98).ignoresSafeArea()
                    
                    switch selectedTab {
                    case 0:
                        transcriptionsTab
                    case 1:
                        presetsTab
                    case 2:
                        aiSettingsTab
                    case 3:
                        glossaryTab
                    case 4:
                        analyticsTab
                    case 5:
                        ollamaTab
                    default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Sidebar View

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Brand
            HStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                Text("MYWISPR FLOW")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(.black)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 24)
            
            // Menu Items
            VStack(spacing: 4) {
                sidebarButton(title: "Cronologia", icon: "waveform", index: 0)
                sidebarButton(title: "Personalizza Preset", icon: "slider.horizontal.3", index: 1)
                sidebarButton(title: "Impostazioni AI", icon: "cpu", index: 2)
                sidebarButton(title: "Glossario Tecnico", icon: "character.book.closed", index: 3)
                sidebarButton(title: "Statistiche & Analytics", icon: "chart.bar.xaxis", index: 4)
                sidebarButton(title: "Monitor Ollama", icon: "speedometer", index: 5)
            }
            .padding(.horizontal, 8)
            
            Spacer()
            
            // Footer - Connessione Status
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.isOllamaConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(state.isOllamaConnected ? "Ollama Connesso" : "Ollama Offline")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(state.isOllamaConnected ? .green : .red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(state.isOllamaConnected ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
                .cornerRadius(4)
                
                Text("Versione 2.0 (Apple Pro)")
                    .font(.system(size: 8))
                    .foregroundColor(Color(white: 0.6))
            }
            .padding(16)
        }
    }

    private func sidebarButton(title: String, icon: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.12)) {
                selectedTab = index
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? .white : Color(white: 0.35))
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                    .foregroundColor(isSelected ? .white : Color(white: 0.2))
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.black : Color.clear)
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail Header

    private var detailHeader: some View {
        HStack {
            Text(tabTitle(for: selectedTab))
                .font(.system(size: 14, weight: .black))
                .foregroundColor(.black)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.white)
    }

    private func tabTitle(for index: Int) -> String {
        switch index {
        case 0: return "CRONOLOGIA E EDITOR"
        case 1: return "GESTIONE PRESET AI"
        case 2: return "IMPOSTAZIONI AI & MODELLI"
        case 3: return "GLOSSARIO REGOLE"
        case 4: return "STATISTICHE & ANALYTICS"
        case 5: return "LIVE MONITOR OLLAMA"
        default: return ""
        }
    }

    // MARK: - Tab 0: Cronologia & Editor

    private var transcriptionsTab: some View {
        HStack(spacing: 0) {
            // Lista Sinistra
            VStack(spacing: 8) {
                // Barra di ricerca
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    TextField("Cerca nello storico...", text: $searchHistoryQuery)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 10))
                }
                .padding(6)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)
                .padding(.horizontal, 10)
                .padding(.top, 8)

                if filteredHistory.isEmpty {
                    VStack {
                        Spacer()
                        Text("Nessun record trovato")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(selection: $selectedRecordId) {
                        ForEach(filteredHistory) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.cleanedText)
                                    .font(.system(size: 11, weight: .bold))
                                    .lineLimit(2)
                                    .foregroundColor(.black)
                                
                                HStack {
                                    Text(record.timestamp, style: .time)
                                        .font(.system(size: 8))
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("\(record.wordCount) parole")
                                        .font(.system(size: 8))
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(selectedRecordId == record.id ? Color.black.opacity(0.06) : Color.white)
                            .cornerRadius(4)
                            .onTapGesture {
                                selectedRecordId = record.id
                                editedCleanedText = record.cleanedText
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                }
            }
            .frame(width: 240)
            .background(Color(white: 0.96))
            
            Divider().background(Color(white: 0.88))
            
            // Dettaglio/Editor Destra
            ZStack {
                if let recordId = selectedRecordId, let record = state.transcriptionHistory.first(where: { $0.id == recordId }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Dettagli Registrazione (\(record.timestamp, style: .date) alle \(record.timestamp, style: .time))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)

                            // Testo Originale (Raw)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("🔈 PARLATO GREZZO")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.red)
                                Text(record.rawText.isEmpty ? "(Silenzio rilevato)" : record.rawText)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(white: 0.45))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(white: 0.95))
                                    .border(Color(white: 0.9), width: 1)
                            }

                            // Editor Testo Pulito
                            VStack(alignment: .leading, spacing: 4) {
                                Text("✨ EDIT TESTO CORRETTO (AI)")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.green)
                                
                                TextEditor(text: $editedCleanedText)
                                    .font(.system(size: 11))
                                    .frame(height: 120)
                                    .padding(4)
                                    .background(Color.white)
                                    .border(Color(white: 0.85), width: 1)
                            }

                            // Bottoni Salva / Copia / Cancella
                            HStack(spacing: 12) {
                                Button(action: {
                                    state.updateRecord(id: record.id, newCleanedText: editedCleanedText)
                                }) {
                                    Text("SALVA MODIFICHE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(Color.black)
                                        .cornerRadius(3)
                                }
                                .buttonStyle(.plain)

                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(editedCleanedText, forType: .string)
                                }) {
                                    Text("COPIA NEGLI APPUNTI")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(Color.clear)
                                        .border(Color.black, width: 1)
                                }
                                .buttonStyle(.plain)
                                
                                Spacer()
                            }

                            Divider().background(Color(white: 0.9))

                            // Ri-elaborazione Testo con Preset
                            VStack(alignment: .leading, spacing: 8) {
                                Text("🔄 RI-ELABORA CON ALTRO PRESET")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.black)
                                
                                HStack(spacing: 10) {
                                    Picker("", selection: $selectedReprocessPreset) {
                                        ForEach(AIPreset.allCases, id: \.self) { preset in
                                            Text(preset.displayName).tag(preset)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 160)
                                    
                                    Button(action: {
                                        reprocessRecord(record)
                                    }) {
                                        HStack {
                                            if isReprocessing {
                                                ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                                            }
                                            Text(isReprocessing ? "ELABORAZIONE..." : "APPLICA PRESET")
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 6)
                                        .background(isReprocessing ? Color.gray : Color.black)
                                        .cornerRadius(3)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isReprocessing)
                                }
                            }
                            .padding(10)
                            .background(Color(white: 0.96))
                            .border(Color(white: 0.95), width: 1)
                        }
                        .padding(16)
                    }
                } else {
                    VStack {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 24))
                            .foregroundColor(.gray)
                        Text("Seleziona una trascrizione per visualizzare o modificarne il testo.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var filteredHistory: [TranscriptionRecord] {
        if searchHistoryQuery.isEmpty {
            return state.transcriptionHistory
        }
        return state.transcriptionHistory.filter {
            $0.cleanedText.localizedCaseInsensitiveContains(searchHistoryQuery) ||
            $0.rawText.localizedCaseInsensitiveContains(searchHistoryQuery)
        }
    }

    private func reprocessRecord(_ record: TranscriptionRecord) {
        guard state.isOllamaConnected else {
            state.triggerOfflineAlert()
            return
        }
        isReprocessing = true
        let reprocessManager = OllamaManager(modelName: state.ollamaModelName)
        
        let glossaryText = state.applyGlossary(to: record.rawText)
        
        reprocessManager.cleanTranscript(
            glossaryText,
            modelName: state.ollamaModelName,
            temperature: state.temperature,
            preset: selectedReprocessPreset,
            customPrompt: state.customPrompt
        ) { cleaned, success in
            isReprocessing = false
            if success && !cleaned.isEmpty {
                editedCleanedText = cleaned
                state.updateRecord(id: record.id, newCleanedText: cleaned)
            } else {
                state.triggerOfflineAlert()
            }
        }
    }

    // MARK: - Tab 1: Gestione Preset AI

    private var presetsTab: some View {
        VStack(spacing: 12) {
            // Lista dei Preset Personalizzati
            VStack(alignment: .leading, spacing: 8) {
                Text("I TUOI PRESET PERSONALIZZATI")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                
                if state.customPresets.isEmpty {
                    VStack {
                        Text("Nessun preset personalizzato creato. Puoi definirne uno sotto.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(Color.white)
                    .border(Color(white: 0.9), width: 1)
                } else {
                    List {
                        ForEach(state.customPresets) { preset in
                            HStack {
                                Image(systemName: preset.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(.black)
                                    .frame(width: 20)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.black)
                                    Text(preset.systemPrompt)
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 12) {
                                    Text("Temp: \(preset.temperature, specifier: "%.1f")")
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray)
                                    
                                    Button(action: {
                                        // Applica il prompt e la temperatura per attivarlo come custom
                                        state.aiPreset = .custom
                                        state.customPrompt = preset.systemPrompt
                                        state.temperature = preset.temperature
                                        state.persistData()
                                    }) {
                                        Text("ATTIVA")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.black)
                                            .cornerRadius(2)
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: {
                                        state.removeCustomPreset(id: preset.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                            .listRowBackground(Color.white)
                        }
                    }
                    .listStyle(.plain)
                    .border(Color(white: 0.9), width: 1)
                    .frame(height: 180)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            Divider().background(Color(white: 0.9)).padding(.horizontal, 20)

            // Form aggiunta Preset
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CREA UN NUOVO PRESET")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    Spacer()
                }

                HStack(spacing: 12) {
                    TextField("Nome Preset (es. E-Mail Formale)", text: $newPresetName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.white)
                        .border(Color(white: 0.8), width: 1)
                        .font(.system(size: 10))
                    
                    Picker("Icona:", selection: $newPresetIcon) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Image(systemName: icon).tag(icon)
                        }
                    }
                    .frame(width: 140)
                    .font(.system(size: 10))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt di elaborazione (Istruzioni fornite al modello LLM):")
                        .font(.system(size: 9, weight: .bold))
                    TextEditor(text: $newPresetPrompt)
                        .font(.system(size: 10))
                        .frame(height: 60)
                        .border(Color(white: 0.8), width: 1)
                        .cornerRadius(2)
                }

                HStack {
                    Slider(value: $newPresetTemp, in: 0.0...1.0, step: 0.1) {
                        Text("Temp AI: \(newPresetTemp, specifier: "%.1f")").font(.system(size: 9))
                    }
                    .accentColor(.black)
                    
                    Spacer(minLength: 20)

                    Button(action: {
                        guard !newPresetName.isEmpty && !newPresetPrompt.isEmpty else { return }
                        state.addCustomPreset(name: newPresetName, icon: newPresetIcon, prompt: newPresetPrompt, temp: newPresetTemp)
                        newPresetName = ""
                        newPresetPrompt = ""
                    }) {
                        Text("SALVA PRESET")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.black)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color.white)
            .border(Color(white: 0.9), width: 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Tab 2: Impostazioni AI & Modelli

    private var aiSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Sezione Configurazione Hotkey
                VStack(alignment: .leading, spacing: 8) {
                    Text("TASTO DI ATTIVAZIONE (HOTKEY)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.4))
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            NotificationCenter.default.post(name: NSNotification.Name("mywispr.startHotkeyRecording"), object: nil)
                        }) {
                            Text(state.isRecordingHotkey ? "PREMI UN TASTO..." : KeyboardManager.keyName(for: state.hotkeyKeyCode).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(state.isRecordingHotkey ? .red : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(state.isRecordingHotkey ? Color.red.opacity(0.1) : Color.black)
                                .border(state.isRecordingHotkey ? Color.red : Color.black, width: 1.5)
                        }
                        .buttonStyle(.plain)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dettatura classica: Tieni premuto per parlare, rilascia per incollare.")
                                .font(.system(size: 9))
                                .foregroundColor(Color(white: 0.5))
                            Text("Ascolto Continuo: Premi due volte per registrare a mani libere. Clicca col mouse o premi nuovamente l'hotkey per interrompere.")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color(white: 0.4))
                        }
                    }
                    
                    if let rejection = state.hotkeyRejectionMessage {
                        Text(rejection)
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                }
                .padding(12)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)
                
                // Sezione Configurazione Modello
                VStack(alignment: .leading, spacing: 10) {
                    Text("MODELLO LOCALE OLLAMA")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.4))
                    
                    if state.availableOllamaModels.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("⚠️ Nessun modello rilevato su Ollama localmente.")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                            Text("Verifica che Ollama sia avviato. Puoi scaricare un modello dal tab 'Monitor Ollama'.")
                                .font(.system(size: 9))
                                .foregroundColor(Color(white: 0.5))
                            
                            TextField("Inserisci nome modello a mano", text: $state.ollamaModelName)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(6)
                                .border(Color.black, width: 1)
                                .font(.system(size: 10))
                        }
                    } else {
                        HStack {
                            Text("Modello attivo:")
                                .font(.system(size: 10))
                                .foregroundColor(Color(white: 0.45))
                            
                            Picker("", selection: $state.ollamaModelName) {
                                ForEach(state.availableOllamaModels, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .labelsHidden()
                            .font(.system(size: 10))
                            .frame(width: 220)
                        }
                    }
                    
                    // Slider Temperatura
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperatura AI: \(state.temperature, specifier: "%.1f")")
                                .font(.system(size: 10, weight: .bold))
                            Spacer()
                            Text(state.temperature <= 0.2 ? "Correzione Letterale" : (state.temperature >= 0.7 ? "Creativo" : "Bilanciato"))
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                        }
                        
                        Slider(value: $state.temperature, in: 0.0...1.0, step: 0.1)
                            .accentColor(.black)
                    }
                    .padding(.top, 4)
                }
                .padding(12)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)
                
                // Sezione Preset di Trascrizione Standard
                VStack(alignment: .leading, spacing: 10) {
                    Text("PRESET DI BASE AI")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.4))
                    
                    Picker("Preset standard attivo:", selection: $state.aiPreset) {
                        ForEach(AIPreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .font(.system(size: 10))
                }
                .padding(12)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)
                
                // Badge dei permessi di sistema
                HStack(spacing: 12) {
                    permissionBadge(label: "Microfono", granted: state.hasMicrophonePermission)
                    permissionBadge(label: "Riconoscimento Vocale", granted: state.hasSpeechPermission)
                    permissionBadge(label: "Accessibilità", granted: state.hasAccessibilityPermission)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func permissionBadge(label: String, granted: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(granted ? Color.green : Color.red)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(white: 0.45))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white)
        .border(Color(white: 0.9), width: 1)
    }

    // MARK: - Tab 3: Glossario Tecnico

    private var glossaryTab: some View {
        VStack(spacing: 0) {
            // Form Aggiunta Elemento
            VStack(alignment: .leading, spacing: 8) {
                Text("AGGIUNGI REGOLA DI SOSTITUZIONE")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(Color(white: 0.4))
                
                HStack(spacing: 8) {
                    TextField("Voce grezza (es. svift)", text: $newWord)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.white)
                        .border(Color(white: 0.8), width: 1)
                        .font(.system(size: 10))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    
                    TextField("Sostituzione corretta (es. Swift)", text: $newReplacement)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.white)
                        .border(Color(white: 0.8), width: 1)
                        .font(.system(size: 10))
                    
                    Button(action: {
                        state.addGlossaryItem(word: newWord, replacement: newReplacement)
                        newWord = ""
                        newReplacement = ""
                    }) {
                        Text("AGGIUNGI")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.black)
                            .cornerRadius(3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color.white)
            .border(Color(white: 0.9), width: 1)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            
            // Tabella delle regole salvate
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("REGOLE ATTIVE (\(state.glossary.count))")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.45))
                    
                    Spacer()
                    
                    // Ricerca regole
                    HStack {
                        Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundColor(.gray)
                        TextField("Cerca nel glossario...", text: $searchGlossaryQuery)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 9))
                            .frame(width: 140)
                    }
                    .padding(4)
                    .background(Color.white)
                    .border(Color(white: 0.9), width: 1)
                }
                
                if filteredGlossary.isEmpty {
                    VStack {
                        Text("Nessuna regola nel glossario.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .border(Color(white: 0.9), width: 1)
                } else {
                    List {
                        ForEach(filteredGlossary.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack {
                                Text(key)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)
                                    .frame(width: 20)
                                
                                Text(value)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.green)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Button(action: {
                                    state.removeGlossaryItem(word: key)
                                }) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(.red)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 2)
                            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                            .listRowBackground(Color.white)
                        }
                    }
                    .listStyle(.plain)
                    .border(Color(white: 0.9), width: 1)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
    }

    private var filteredGlossary: [String: String] {
        if searchGlossaryQuery.isEmpty {
            return state.glossary
        }
        return state.glossary.filter {
            $0.key.localizedCaseInsensitiveContains(searchGlossaryQuery) ||
            $0.value.localizedCaseInsensitiveContains(searchGlossaryQuery)
        }
    }

    // MARK: - Tab 4: Analytics

    private var analyticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // KPI Summary Cards
                HStack(spacing: 12) {
                    kpiCard(title: "PAROLE DETTATE", value: "\(state.totalWords)", subtitle: "Produttività vocale")
                    kpiCard(title: "TEMPO RISPARMIATO", value: formatTime(state.timeSavedSeconds), subtitle: "Velocità media stimata")
                    kpiCard(title: "EFFICACIA", value: "+375%", subtitle: "Rispetto a tastiera manuale")
                }
                .padding(.top, 10)
                
                // Grafico Dettatura Giornaliera (SwiftUI Charts)
                VStack(alignment: .leading, spacing: 10) {
                    Text("PAROLE DETTATE NEGLI ULTIMI 7 GIORNI")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    
                    if dailyChartData.isEmpty {
                        VStack {
                            Text("Dati insufficienti per generare il grafico. Inizia a dettare testo!")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .background(Color.white)
                        .border(Color(white: 0.9), width: 1)
                    } else {
                        Chart {
                            ForEach(dailyChartData) { data in
                                BarMark(
                                    x: .value("Giorno", data.dayLabel),
                                    y: .value("Parole", data.words)
                                )
                                .foregroundStyle(Color.black)
                                .cornerRadius(3)
                            }
                        }
                        .frame(height: 160)
                        .padding(14)
                        .background(Color.white)
                        .border(Color(white: 0.9), width: 1)
                    }
                }
                
                // Statistiche globali di utilizzo
                VStack(alignment: .leading, spacing: 10) {
                    Text("STATISTICHE DETTAGLIATE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    
                    VStack(spacing: 0) {
                        statRow(label: "Trascrizioni totali effettuate", value: "\(state.transcriptionHistory.count)")
                        Divider().background(Color(white: 0.95))
                        statRow(label: "Lunghezza media trascrizione", value: String(format: "%.1f parole", Double(state.totalWords) / max(1.0, Double(state.transcriptionHistory.count))))
                        Divider().background(Color(white: 0.95))
                        statRow(label: "Modello LLM locale preferito", value: state.ollamaModelName)
                    }
                    .background(Color.white)
                    .border(Color(white: 0.9), width: 1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color(white: 0.55))
            Text(value)
                .font(.system(size: 16, weight: .black))
                .foregroundColor(.black)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundColor(Color(white: 0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white)
        .border(Color(white: 0.9), width: 1)
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.35))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // Struttura dati per grafico SwiftUI Charts
    struct DailyStat: Identifiable {
        let id = UUID()
        let date: Date
        let words: Int
        
        var dayLabel: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM"
            return formatter.string(from: date)
        }
    }

    private var dailyChartData: [DailyStat] {
        var groups: [String: (Date, Int)] = [:]
        let calendar = Calendar.current
        
        // Inizializza gli ultimi 7 giorni a 0
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let key = calendar.startOfDay(for: date).description
                groups[key] = (date, 0)
            }
        }
        
        // Raggruppa i dati storici
        for record in state.transcriptionHistory {
            let key = calendar.startOfDay(for: record.timestamp).description
            if let val = groups[key] {
                groups[key] = (val.0, val.1 + record.wordCount)
            }
        }
        
        return groups.values
            .map { DailyStat(date: $0.0, words: $0.1) }
            .sorted(by: { $0.date < $1.date })
    }

    // MARK: - Tab 5: Ollama Monitor

    private var ollamaTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Monitor delle RAM/VRAM e dei Modelli in esecuzione
                VStack(alignment: .leading, spacing: 10) {
                    Text("MODELLI ATTUALMENTE IN ESECUZIONE NELLA RAM/VRAM")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    
                    if !state.isOllamaConnected {
                        Text("Connessione a Ollama non stabilita.")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.white)
                            .border(Color(white: 0.9), width: 1)
                    } else if state.availableOllamaModels.isEmpty {
                        Text("Nessun modello caricato in memoria in questo istante.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color.white)
                            .border(Color(white: 0.9), width: 1)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(state.availableOllamaModels, id: \.self) { name in
                                HStack {
                                    Image(systemName: "cpu.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                    Text(name)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.black)
                                    Spacer()
                                    Text("Attivo (5m timeout)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                        }
                        .background(Color.white)
                        .border(Color(white: 0.9), width: 1)
                    }
                }
                
                // Downloader Modelli (Pull API)
                VStack(alignment: .leading, spacing: 10) {
                    Text("SCARICA NUOVO MODELLO DA OLLAMA REGISTRY")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    
                    Text("Inserisci il nome esatto del modello da scaricare (es: qwen2.5:7b, qwen2.5:3b, llama3).")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 12) {
                        TextField("Esempio: qwen2.5:7b", text: $pullModelName)
                            .textFieldStyle(PlainTextFieldStyle())
                            .padding(6)
                            .background(Color.white)
                            .border(Color(white: 0.8), width: 1)
                            .font(.system(size: 10))
                            .disabled(isPulling)
                        
                        Button(action: {
                            pullModelFromRegistry()
                        }) {
                            HStack {
                                if isPulling {
                                    ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                                }
                                Text(isPulling ? "SCARICAMENTO..." : "SCARICA MODELLO")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(isPulling ? Color.gray : Color.black)
                            .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .disabled(isPulling || pullModelName.isEmpty)
                    }
                    
                    if !pullStatusMessage.isEmpty {
                        Text(pullStatusMessage)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                            .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func pullModelFromRegistry() {
        guard state.isOllamaConnected else {
            pullStatusMessage = "Impossibile scaricare: Ollama offline."
            return
        }
        let model = pullModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        
        isPulling = true
        pullStatusMessage = "Inizio download per \(model)... potrebbe richiedere tempo."
        
        guard let url = URL(string: "http://127.0.0.1:11434/api/pull") else {
            isPulling = false
            pullStatusMessage = "URL non valido."
            return
        }
        
        let body = ["name": model, "stream": false] as [String : Any]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            isPulling = false
            pullStatusMessage = "Errore di serializzazione."
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.timeoutInterval = 600 // Alto timeout per il download
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isPulling = false
                if let error = error {
                    self.pullStatusMessage = "Errore durante il download: \(error.localizedDescription)"
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    self.pullStatusMessage = "Errore: Modello non trovato o server in errore."
                    return
                }
                
                self.pullStatusMessage = "Modello \(model) scaricato con successo!"
                self.pullModelName = ""
                
                // Aggiorna la lista dei modelli disponibili
                NotificationCenter.default.post(name: NSNotification.Name("mywispr.refreshOllama"), object: nil)
            }
        }.resume()
    }

    // MARK: - Onboarding View
    
    private var onboardingView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.black)
                
                Text("Benvenuto in MyWispr")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                
                Text("Per iniziare ad utilizzare la dettatura vocale locale intelligente, configura i permessi richiesti dal sistema operativo.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 30)
            
            VStack(spacing: 12) {
                // Step 1: Microfono
                onboardingStep(
                    icon: "mic.fill",
                    title: "Accesso al Microfono",
                    description: "Necessario per catturare la tua voce durante la dettatura.",
                    granted: state.hasMicrophonePermission,
                    action: {
                        AVCaptureDevice.requestAccess(for: .audio) { granted in
                            DispatchQueue.main.async {
                                state.hasMicrophonePermission = granted
                            }
                        }
                    }
                )
                
                // Step 2: Riconoscimento vocale
                onboardingStep(
                    icon: "brain.head.profile",
                    title: "Riconoscimento Vocale",
                    description: "Abilita macOS a trascrivere il parlato in testo.",
                    granted: state.hasSpeechPermission,
                    action: {
                        SFSpeechRecognizer.requestAuthorization { status in
                            DispatchQueue.main.async {
                                state.hasSpeechPermission = (status == .authorized)
                            }
                        }
                    }
                )
                
                // Step 3: Accessibilità
                onboardingStep(
                    icon: "keyboard.fill",
                    title: "Accesso all'Accessibilità",
                    description: "Necessario per rilevare l'hotkey globale e incollare il testo elaborato.",
                    granted: state.hasAccessibilityPermission,
                    action: {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(options)
                    }
                )
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            if state.hasMicrophonePermission && state.hasSpeechPermission && state.hasAccessibilityPermission {
                Button(action: {
                    // Cliccando sul pulsante, l'onboarding sparisce perché le proprietà di stato si aggiornano
                }) {
                    Text("PROCEDI ALLA DASHBOARD")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.black)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 30)
            } else {
                Text("⚠️ Abilita tutte le autorizzazioni sopra indicate per procedere.")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.bottom, 30)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.98))
    }
    
    private func onboardingStep(icon: String, title: String, description: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(granted ? .green : .gray)
                .frame(width: 24, height: 24)
                .background(granted ? Color.green.opacity(0.08) : Color(white: 0.92))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.black)
                
                Text(description)
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.5))
            }
            
            Spacer()
            
            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 11))
                    Text("CONCESSO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
            } else {
                Button(action: action) {
                    Text("CONCEDI")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black)
                        .cornerRadius(3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.white)
        .border(Color(white: 0.9), width: 1)
    }

    private func formatTime(_ secs: Double) -> String {
        let s = Int(secs)
        if s < 60     { return "\(s)s" }
        if s < 3600   { return "\(s/60)m \(s%60)s" }
        return "\(s/3600)h \((s%3600)/60)m"
    }
}
