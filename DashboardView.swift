import SwiftUI
import Speech
import AVFoundation

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    @State private var selectedTab: Int = 0 // 0 = Trascrizioni, 1 = AI & Modelli, 2 = Glossario
    @State private var copiedId: UUID? = nil
    @State private var expandedDiffId: UUID? = nil
    
    // Form inserimento glossario
    @State private var newWord: String = ""
    @State private var newReplacement: String = ""

    var body: some View {
        VStack(spacing: 0) {
            if !state.hasSpeechPermission || !state.hasMicrophonePermission || !state.hasAccessibilityPermission {
                onboardingView
            } else {
                header
                Divider().background(Color(white: 0.88))
                
                // Tab Navigation
                tabBar
                Divider().background(Color(white: 0.9))
                
                // Tab Content
                ZStack {
                    Color(white: 0.98).ignoresSafeArea()
                    
                    switch selectedTab {
                    case 0:
                        transcriptionsTab
                    case 1:
                        aiSettingsTab
                    case 2:
                        glossaryTab
                    default:
                        EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 550, height: 530)
        .background(Color.white)
        .preferredColorScheme(.light)
        .background(
            Group {
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) { EmptyView() }
                .keyboardShortcut("q", modifiers: .command)

                Button(action: {
                    NotificationCenter.default.post(name: .toggleDashboard, object: nil)
                }) { EmptyView() }
                .keyboardShortcut("d", modifiers: .command)
            }
            .opacity(0)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("MYWISPR FLOW")
                        .font(.system(size: 16))
                        .fontWeight(.black)
                        .foregroundColor(.black)
                    
                    // Connessione Ollama status badge
                    HStack(spacing: 4) {
                        Circle()
                            .fill(state.isOllamaConnected ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                        Text(state.isOllamaConnected ? "OLLAMA ATTIVO" : "OLLAMA OFFLINE")
                            .font(.system(size: 8))
                            .fontWeight(.bold)
                            .foregroundColor(state.isOllamaConnected ? .green : .red)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(state.isOllamaConnected ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
                    .cornerRadius(4)
                }
                
                Text("Dettatura locale intelligente con intelligenza artificiale")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.5))
            }
            Spacer()
            
            // Info versione o stato
            Text("v1.2")
                .font(.system(size: 10))
                .fontWeight(.bold)
                .foregroundColor(Color(white: 0.7))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white)
    }

    // MARK: - Custom Tab Bar

    private var tabBar: some View {
        HStack(spacing: 20) {
            tabButton(title: "TRASOCRIZIONI", icon: "waveform", index: 0)
            tabButton(title: "AI & MODELLI", icon: "cpu", index: 1)
            tabButton(title: "GLOSSARIO", icon: "character.book.closed", index: 2)
            Spacer()
        }
        .padding(.horizontal, 20)
        .background(Color.white)
    }

    private func tabButton(title: String, icon: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = index
            }
        }) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                    Text(title)
                        .font(.system(size: 10))
                        .fontWeight(.black)
                }
                .foregroundColor(isSelected ? .black : Color(white: 0.55))
                
                // Indicatore barra inferiore
                Rectangle()
                    .fill(isSelected ? Color.black : Color.clear)
                    .frame(height: 2)
            }
            .padding(.top, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab 1: Trascrizioni & Cronologia

    private var transcriptionsTab: some View {
        VStack(spacing: 0) {
            // KPI Statistiche riassuntive
            HStack(spacing: 12) {
                kpiCard(title: "PAROLE DETTATE", value: "\(state.totalWords)", subtitle: "Produttività vocale")
                kpiCard(title: "TEMPO RISPARMIATO", value: formatTime(state.timeSavedSeconds), subtitle: "Velocità media stimata")
                kpiCard(title: "HOTKEY CORRENTE", value: KeyboardManager.keyName(for: state.hotkeyKeyCode).uppercased(), subtitle: "Tasto premuto")
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Lista cronologia
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CRONOLOGIA TRASCRIZIONI")
                        .font(.system(size: 10))
                        .fontWeight(.black)
                        .foregroundColor(Color(white: 0.45))
                    Spacer()
                    if !state.transcriptionHistory.isEmpty {
                        Button(action: { state.clearHistory() }) {
                            Text("AZZERA TUTTO")
                                .font(.system(size: 9))
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                
                if state.transcriptionHistory.isEmpty {
                    emptyHistoryView
                } else {
                    List {
                        ForEach(state.transcriptionHistory) { record in
                            historyRow(record)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 8))
                .fontWeight(.bold)
                .foregroundColor(Color(white: 0.55))
            Text(value)
                .font(.system(size: 14))
                .fontWeight(.black)
                .foregroundColor(.black)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 8))
                .foregroundColor(Color(white: 0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white)
        .border(Color(white: 0.9), width: 1)
        .shadow(color: Color.black.opacity(0.01), radius: 3, x: 0, y: 1)
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 24))
                .foregroundColor(Color(white: 0.7))
            Text("Nessuna trascrizione registrata")
                .font(.system(size: 11))
                .fontWeight(.bold)
                .foregroundColor(Color(white: 0.6))
            Text("Tieni premuto il tuo Hotkey per dettare il testo.")
                .font(.system(size: 9))
                .foregroundColor(Color(white: 0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .border(Color(white: 0.9), width: 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func historyRow(_ record: TranscriptionRecord) -> some View {
        let isExpanded = expandedDiffId == record.id
        
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Testo elaborato principale
                        Text(record.cleanedText)
                            .font(.system(size: 12))
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Text(record.timestamp, style: .time)
                            .font(.system(size: 9))
                            .foregroundColor(Color(white: 0.6))
                    }
                    
                    Spacer(minLength: 10)
                    
                    HStack(spacing: 8) {
                        // Bottone Diff Viewer
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                expandedDiffId = isExpanded ? nil : record.id
                            }
                        }) {
                            Text(isExpanded ? "NASCONDI COMPARA" : "CONFRONTA AI")
                                .font(.system(size: 8))
                                .fontWeight(.bold)
                                .foregroundColor(isExpanded ? .black : Color(white: 0.45))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(isExpanded ? Color(white: 0.9) : Color.clear)
                                .border(Color(white: 0.8), width: 1)
                        }
                        .buttonStyle(.plain)

                        // Bottone Copia
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(record.cleanedText, forType: .string)
                            copiedId = record.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                if copiedId == record.id { copiedId = nil }
                            }
                        }) {
                            Text(copiedId == record.id ? "COPIATO" : "COPIA")
                                .font(.system(size: 8))
                                .fontWeight(.bold)
                                .foregroundColor(copiedId == record.id ? .white : .black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(copiedId == record.id ? Color.black : Color.clear)
                                .border(Color.black, width: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Pannello Diff Espanso (Mostra il confronto tra parlato grezzo e corretto)
                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 4) {
                            Text("🔈 PARLATO GREZZO:")
                                .font(.system(size: 8))
                                .fontWeight(.black)
                                .foregroundColor(.red)
                                .frame(width: 100, alignment: .leading)
                            Text(record.rawText.isEmpty ? "(nessun suono rilevato)" : record.rawText)
                                .font(.system(size: 10))
                                .foregroundColor(Color(white: 0.45))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                        
                        Divider().background(Color(white: 0.9))
                        
                        HStack(alignment: .top, spacing: 4) {
                            Text("✨ CORRETTO DA AI:")
                                .font(.system(size: 8))
                                .fontWeight(.black)
                                .foregroundColor(.green)
                                .frame(width: 100, alignment: .leading)
                            Text(record.cleanedText)
                                .font(.system(size: 10))
                                .foregroundColor(.black)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.bottom, 4)
                    }
                    .padding(8)
                    .background(Color(white: 0.96))
                    .border(Color(white: 0.88), width: 1)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(12)
            .background(Color.white)
            .border(Color(white: 0.9), width: 1)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Tab 2: AI & Impostazioni Modelli

    private var aiSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                
                // Sezione Configurazione Hotkey
                VStack(alignment: .leading, spacing: 8) {
                    Text("TASTO DI ATTIVAZIONE (HOTKEY)")
                        .font(.system(size: 10))
                        .fontWeight(.black)
                        .foregroundColor(Color(white: 0.4))
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            NotificationCenter.default.post(name: .startHotkeyRecording, object: nil)
                        }) {
                            Text(state.isRecordingHotkey ? "PREMI UN TASTO..." : KeyboardManager.keyName(for: state.hotkeyKeyCode).uppercased())
                                .font(.system(size: 10))
                                .fontWeight(.bold)
                                .foregroundColor(state.isRecordingHotkey ? .red : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(state.isRecordingHotkey ? Color.red.opacity(0.1) : Color.black)
                                .border(state.isRecordingHotkey ? Color.red : Color.black, width: 1.5)
                        }
                        .buttonStyle(.plain)
                        
                        Text("Tieni premuto questo tasto per parlare, rilascialo per trascrivere e incollare.")
                            .font(.system(size: 9))
                            .foregroundColor(Color(white: 0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    if let rejection = state.hotkeyRejectionMessage {
                        Text(rejection)
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                            .padding(.top, 2)
                    }
                }
                .padding(12)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)
                
                // Sezione Configurazione Modello
                VStack(alignment: .leading, spacing: 10) {
                    Text("MODELLO LOCALE OLLAMA")
                        .font(.system(size: 10))
                        .fontWeight(.black)
                        .foregroundColor(Color(white: 0.4))
                    
                    if state.availableOllamaModels.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("⚠️ Nessun modello rilevato su Ollama localmente.")
                                .font(.system(size: 10))
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                            Text("Verifica che Ollama sia in esecuzione (porta 11434) e di aver scaricato un modello (es. 'ollama run qwen2.5:14b' nel terminale). Usando input testuale di fallback:")
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
                                .font(.system(size: 10))
                                .fontWeight(.bold)
                            Spacer()
                            Text(state.temperature <= 0.2 ? "Correzione Letterale" : (state.temperature >= 0.7 ? "Molto Creativo" : "Bilanciato"))
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
                
                // Sezione Preset di Trascrizione
                VStack(alignment: .leading, spacing: 10) {
                    Text("PRESET DI ELABORAZIONE AI")
                        .font(.system(size: 10))
                        .fontWeight(.black)
                        .foregroundColor(Color(white: 0.4))
                    
                    Picker("Preset AI:", selection: $state.aiPreset) {
                        ForEach(AIPreset.allCases, id: \.self) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .font(.system(size: 10))
                    
                    if state.aiPreset == .custom {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Istruzione Custom Prompt:")
                                .font(.system(size: 9))
                                .fontWeight(.bold)
                                .foregroundColor(.black)
                            
                            TextEditor(text: $state.customPrompt)
                                .font(.system(size: 10))
                                .frame(height: 70)
                                .border(Color(white: 0.8), width: 1)
                                .cornerRadius(2)
                            
                            Text("Scrivi l'istruzione esatta per l'AI. Esempio: 'Correggi e formatta come codice Swift' o 'Traduci in dialetto milanese'.")
                                .font(.system(size: 8))
                                .foregroundColor(.gray)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(12)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)
                
                // Badge dei permessi di sistema
                HStack(spacing: 12) {
                    permissionBadge(label: "Microfono", granted: state.hasMicrophonePermission)
                    permissionBadge(label: "Riconoscimento Vocale", granted: state.hasSpeechPermission)
                    permissionBadge(label: "Accessibilità", granted: AXIsProcessTrusted())
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
                .font(.system(size: 8))
                .fontWeight(.bold)
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
                    .font(.system(size: 10))
                    .fontWeight(.black)
                    .foregroundColor(Color(white: 0.4))
                
                Text("Utile per correggere parole che macOS capisce male. Es: 'tulle' viene sostituito automaticamente con 'tool'.")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.5))
                
                HStack(spacing: 8) {
                    TextField("Voce grezza (es. tulle)", text: $newWord)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.white)
                        .border(Color(white: 0.8), width: 1)
                        .font(.system(size: 10))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    
                    TextField("Sostituzione (es. tool)", text: $newReplacement)
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
                            .font(.system(size: 9))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.black)
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
                Text("REGOLE ATTIVE (\(state.glossary.count))")
                    .font(.system(size: 10))
                    .fontWeight(.black)
                    .foregroundColor(Color(white: 0.45))
                
                if state.glossary.isEmpty {
                    VStack {
                        Text("Nessuna regola inserita.")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .border(Color(white: 0.9), width: 1)
                } else {
                    List {
                        ForEach(state.glossary.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                            HStack {
                                Text(key)
                                    .font(.system(size: 11))
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(.gray)
                                    .frame(width: 20)
                                
                                Text(value)
                                    .font(.system(size: 11))
                                    .fontWeight(.bold)
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
                            .padding(.vertical, 4)
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

    // MARK: - Utils

    private func formatTime(_ secs: Double) -> String {
        let s = Int(secs)
        if s < 60     { return "\(s)s" }
        if s < 3600   { return "\(s/60)m \(s%60)s" }
        return "\(s/3600)h \((s%3600)/60)m"
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
}

// MARK: - Notification Names

extension Notification.Name {
    static let startHotkeyRecording = Notification.Name("mywispr.startHotkeyRecording")
    static let toggleDashboard = Notification.Name("mywispr.toggleDashboard")
}
