import SwiftUI
import Speech
import AVFoundation
import Charts

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    /// Stateless client for the local Ollama server, used by the reprocess and pull actions.
    private let ollama = OllamaManager()

    // 0 = History, 1 = Presets, 2 = AI Settings, 3 = Glossary, 4 = Analytics, 5 = Ollama Monitor
    @State private var selectedTab: Int = 0
    
    // History tab state
    @State private var selectedRecordId: UUID? = nil
    @State private var editedCleanedText: String = ""
    @State private var selectedReprocessPreset: AIPreset = .standard
    @State private var isReprocessing: Bool = false
    @State private var searchHistoryQuery: String = ""

    // Preset tab state
    @State private var newPresetName: String = ""
    @State private var newPresetIcon: String = "doc.text.fill"
    @State private var newPresetPrompt: String = ""
    @State private var newPresetTemp: Double = 0.3
    @State private var showAddPresetForm: Bool = false

    // Glossary tab state
    @State private var newWord: String = ""
    @State private var newReplacement: String = ""
    @State private var searchGlossaryQuery: String = ""

    // Ollama Monitor tab state
    @State private var pullModelName: String = ""
    @State private var pullStatusMessage: String = ""
    @State private var isPulling: Bool = false

    // Icons offered when creating a custom preset
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
                    NotificationCenter.default.post(name: .mywisprToggleDashboard, object: nil)
                }) { EmptyView() }
                .keyboardShortcut("d", modifiers: .command)
            }
            .opacity(0)
        )
        .onAppear {
            state.refreshPermissions()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermissions()
        }
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
            // App brand
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
            
            // Menu items
            VStack(spacing: 4) {
                sidebarButton(title: state.l10n.sidebarHistory, icon: "waveform", index: 0)
                sidebarButton(title: state.l10n.sidebarPresets, icon: "slider.horizontal.3", index: 1)
                sidebarButton(title: state.l10n.sidebarSettings, icon: "cpu", index: 2)
                sidebarButton(title: state.l10n.sidebarGlossary, icon: "character.book.closed", index: 3)
                sidebarButton(title: state.l10n.sidebarAnalytics, icon: "chart.bar.xaxis", index: 4)
                sidebarButton(title: state.l10n.sidebarMonitor, icon: "speedometer", index: 5)
            }
            .padding(.horizontal, 8)
            
            Spacer()
            
            // Footer - connection status
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.isOllamaConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(state.isOllamaConnected ? state.l10n.sidebarOllamaConnected : state.l10n.sidebarOllamaOffline)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(state.isOllamaConnected ? .green : .red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(state.isOllamaConnected ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
                .cornerRadius(4)
                
                Text(state.l10n.sidebarVersion(Bundle.main.appVersion))
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
        case 0: return state.l10n.tabTitleHistory
        case 1: return state.l10n.tabTitlePresets
        case 2: return state.l10n.tabTitleSettings
        case 3: return state.l10n.tabTitleGlossary
        case 4: return state.l10n.tabTitleAnalytics
        case 5: return state.l10n.tabTitleMonitor
        default: return ""
        }
    }

    // MARK: - Tab 0: History & Editor

    private var transcriptionsTab: some View {
        HStack(spacing: 0) {
            // Left-hand list
            VStack(spacing: 8) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    TextField(state.l10n.historySearchPlaceholder, text: $searchHistoryQuery)
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
                        Text(state.l10n.historyNoRecords)
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
                                    Text(state.l10n.historyWordCount(record.wordCount))
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
            
            // Right-hand detail / editor
            ZStack {
                if let recordId = selectedRecordId, let record = state.transcriptionHistory.first(where: { $0.id == recordId }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("\(state.l10n.historyRecordDetails) (\(record.timestamp, style: .date) \(state.l10n.historyAt) \(record.timestamp, style: .time))")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.gray)

                            // Original (raw) text
                            VStack(alignment: .leading, spacing: 4) {
                                Text(state.l10n.historyRawSpeech)
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.red)
                                Text(record.rawText.isEmpty ? state.l10n.historySilenceDetected : record.rawText)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(white: 0.45))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(white: 0.95))
                                    .border(Color(white: 0.9), width: 1)
                            }

                            // Cleaned-text editor
                            VStack(alignment: .leading, spacing: 4) {
                                Text(state.l10n.historyEditedText)
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.green)
                                
                                TextEditor(text: $editedCleanedText)
                                    .font(.system(size: 11))
                                    .frame(height: 120)
                                    .padding(4)
                                    .background(Color.white)
                                    .border(Color(white: 0.85), width: 1)
                            }

                            // Save / Copy / Delete buttons
                            HStack(spacing: 12) {
                                Button(action: {
                                    state.updateRecord(id: record.id, newCleanedText: editedCleanedText)
                                }) {
                                    Text(state.l10n.historySaveChanges)
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
                                    Text(state.l10n.historyCopyClipboard)
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

                            // Re-run the text through a different preset
                            VStack(alignment: .leading, spacing: 8) {
                                Text(state.l10n.historyReprocess)
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundColor(.black)
                                
                                HStack(spacing: 10) {
                                    Picker("", selection: $selectedReprocessPreset) {
                                        ForEach(AIPreset.allCases, id: \.self) { preset in
                                            Text(state.l10n.presetName(preset)).tag(preset)
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
                                            Text(isReprocessing ? state.l10n.historyProcessing : state.l10n.historyApplyPreset)
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
                        Text(state.l10n.historyEmptySelection)
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

        let glossaryText = state.applyGlossary(to: record.rawText)

        ollama.cleanTranscript(
            glossaryText,
            modelName: state.ollamaModelName,
            temperature: state.temperature,
            preset: selectedReprocessPreset,
            customPrompt: state.customPrompt,
            language: state.dictationLanguage
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

    // MARK: - Tab 1: AI Preset Management

    private var presetsTab: some View {
        VStack(spacing: 12) {
            // List of custom presets
            VStack(alignment: .leading, spacing: 8) {
                Text(state.l10n.presetsYourCustom)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(white: 0.45))
                
                if state.customPresets.isEmpty {
                    VStack {
                        Text(state.l10n.presetsEmpty)
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
                                    Text(state.l10n.presetsTemp(preset.temperature))
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray)
                                    
                                    Button(action: {
                                        // Apply the prompt and temperature, activating it as the custom preset
                                        state.aiPreset = .custom
                                        state.customPrompt = preset.systemPrompt
                                        state.temperature = preset.temperature
                                        state.persistData()
                                    }) {
                                        Text(state.l10n.presetsActivate)
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

            // Add-preset form
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(state.l10n.presetsCreateNew)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    Spacer()
                }

                HStack(spacing: 12) {
                    TextField(state.l10n.presetsNamePlaceholder, text: $newPresetName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.white)
                        .border(Color(white: 0.8), width: 1)
                        .font(.system(size: 10))
                    
                    Picker(state.l10n.presetsIconLabel, selection: $newPresetIcon) {
                        ForEach(availableIcons, id: \.self) { icon in
                            Image(systemName: icon).tag(icon)
                        }
                    }
                    .frame(width: 140)
                    .font(.system(size: 10))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.l10n.presetsPromptLabel)
                        .font(.system(size: 9, weight: .bold))
                    TextEditor(text: $newPresetPrompt)
                        .font(.system(size: 10))
                        .frame(height: 60)
                        .border(Color(white: 0.8), width: 1)
                        .cornerRadius(2)
                }

                HStack {
                    Slider(value: $newPresetTemp, in: 0.0...1.0, step: 0.1) {
                        Text(state.l10n.presetsAITemp(newPresetTemp)).font(.system(size: 9))
                    }
                    .accentColor(.black)
                    
                    Spacer(minLength: 20)

                    Button(action: {
                        guard !newPresetName.isEmpty && !newPresetPrompt.isEmpty else { return }
                        state.addCustomPreset(name: newPresetName, icon: newPresetIcon, prompt: newPresetPrompt, temp: newPresetTemp)
                        newPresetName = ""
                        newPresetPrompt = ""
                    }) {
                        Text(state.l10n.presetsSave)
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

    // MARK: - Tab 2: AI Settings & Models

    private var aiSettingsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Hotkey configuration
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.l10n.settingsHotkeySection)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.4))
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            NotificationCenter.default.post(name: .mywisprStartHotkeyRecording, object: nil)
                        }) {
                            Text(state.isRecordingHotkey ? state.l10n.settingsPressAKey : state.l10n.keyName(for: state.hotkeyKeyCode).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(state.isRecordingHotkey ? .red : .white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(state.isRecordingHotkey ? Color.red.opacity(0.1) : Color.black)
                                .border(state.isRecordingHotkey ? Color.red : Color.black, width: 1.5)
                        }
                        .buttonStyle(.plain)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.l10n.settingsHoldToTalk)
                                .font(.system(size: 9))
                                .foregroundColor(Color(white: 0.5))
                            Text(state.l10n.settingsLockToListen)
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
                
                // Model configuration
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.l10n.settingsModelSection)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.4))
                    
                    if state.availableOllamaModels.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(state.l10n.settingsNoModelDetected)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                            Text(state.l10n.settingsNoModelHint)
                                .font(.system(size: 9))
                                .foregroundColor(Color(white: 0.5))
                            
                            TextField(state.l10n.settingsManualModel, text: $state.ollamaModelName)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(6)
                                .border(Color.black, width: 1)
                                .font(.system(size: 10))
                        }
                    } else {
                        HStack {
                            Text(state.l10n.settingsActiveModel)
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
                    
                    // Temperature slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(state.l10n.settingsTemperature(state.temperature))
                                .font(.system(size: 10, weight: .bold))
                            Spacer()
                            Text(state.temperature <= 0.2 ? state.l10n.settingsTempLiteral : (state.temperature >= 0.7 ? state.l10n.settingsTempCreative : state.l10n.settingsTempBalanced))
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
                
                // Built-in transcription presets
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.l10n.settingsBasePresets)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.4))
                    
                    Picker(state.l10n.settingsActivePreset, selection: $state.aiPreset) {
                        ForEach(AIPreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                            Text(state.l10n.presetName(preset)).tag(preset)
                        }
                    }
                    .font(.system(size: 10))
                }
                .padding(12)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)
                
                // Language: one picker drives both the recognition locale and the UI.
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.l10n.languageSection)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.4))

                    HStack(spacing: 12) {
                        Text(state.l10n.languageLabel)
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.45))

                        Picker("", selection: languageBinding) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text("\(lang.flag)  \(lang.displayName)").tag(lang)
                            }
                        }
                        .labelsHidden()
                        .font(.system(size: 10))
                        .frame(width: 160)
                        // Changing the recogniser mid-session would tear down a live
                        // audio tap, so the picker is locked while recording.
                        .disabled(state.isRecording)

                        Spacer()
                    }

                    Text(state.isRecording ? state.l10n.languageBusyWarning : state.l10n.languageHint)
                        .font(.system(size: 9))
                        .foregroundColor(state.isRecording ? .orange : Color(white: 0.5))

                    if !SpeechManager.isSupported(state.dictationLanguage) {
                        Text(state.l10n.languageUnsupported)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
                .padding(12)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)

                // Privacy: report what actually happens to the audio and the text,
                // rather than a blanket "everything is local" claim.
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.l10n.privacySection)
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.4))

                    HStack(spacing: 6) {
                        Image(systemName: state.isOnDeviceRecognition ? "lock.fill" : "cloud.fill")
                            .font(.system(size: 10))
                            .foregroundColor(state.isOnDeviceRecognition ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.isOnDeviceRecognition
                                 ? state.l10n.privacyOnDevice
                                 : state.l10n.privacyServerBased)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(state.isOnDeviceRecognition ? .green : .orange)
                            if !state.isOnDeviceRecognition {
                                Text(state.l10n.privacyServerHint)
                                    .font(.system(size: 9))
                                    .foregroundColor(Color(white: 0.5))
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                        Text(state.l10n.privacyLocalAI)
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.35))
                    }

                    Divider()

                    Toggle(isOn: $state.verboseLogging) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.l10n.privacyVerboseToggle)
                                .font(.system(size: 10, weight: .bold))
                            Text(state.l10n.privacyVerboseHint)
                                .font(.system(size: 9))
                                .foregroundColor(Color(white: 0.5))
                        }
                    }
                    .toggleStyle(.switch)

                    HStack(spacing: 8) {
                        Text(Logger.logURL.path)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(Color(white: 0.55))
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button(action: { Logger.clear() }) {
                            Text(state.l10n.privacyClearLog)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Color(white: 0.35))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .border(Color(white: 0.8), width: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.white)
                .border(Color(white: 0.9), width: 1)

                // System permission badges
                HStack(spacing: 12) {
                    permissionBadge(label: state.l10n.permMicrophone, granted: state.hasMicrophonePermission)
                    permissionBadge(label: state.l10n.permSpeech, granted: state.hasSpeechPermission)
                    permissionBadge(label: state.l10n.permAccessibility, granted: state.hasAccessibilityPermission)
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

    // MARK: - Tab 3: Technical Glossary

    private var glossaryTab: some View {
        VStack(spacing: 0) {
            // Add-entry form
            VStack(alignment: .leading, spacing: 8) {
                Text(state.l10n.glossaryAddRule)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(Color(white: 0.4))
                
                HStack(spacing: 8) {
                    TextField(state.l10n.glossaryRawPlaceholder, text: $newWord)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(6)
                        .background(Color.white)
                        .border(Color(white: 0.8), width: 1)
                        .font(.system(size: 10))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    
                    TextField(state.l10n.glossaryReplacementPlaceholder, text: $newReplacement)
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
                        Text(state.l10n.glossaryAdd)
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
            
            // Table of saved rules
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(state.l10n.glossaryActiveRules(state.glossary.count))
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(Color(white: 0.45))
                    
                    Spacer()
                    
                    // Rule search
                    HStack {
                        Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundColor(.gray)
                        TextField(state.l10n.glossarySearchPlaceholder, text: $searchGlossaryQuery)
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
                        Text(state.l10n.glossaryEmpty)
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
                // KPI summary cards
                HStack(spacing: 12) {
                    kpiCard(title: state.l10n.analyticsWordsDictated, value: "\(state.totalWords)", subtitle: state.l10n.analyticsWordsSubtitle)
                    kpiCard(title: state.l10n.analyticsTimeSaved, value: formatTime(state.timeSavedSeconds), subtitle: state.l10n.analyticsTimeSubtitle)
                    kpiCard(title: state.l10n.analyticsEffectiveness, value: "+375%", subtitle: state.l10n.analyticsEffectivenessSubtitle)
                }
                .padding(.top, 10)
                
                // Daily dictation chart (SwiftUI Charts)
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.l10n.analyticsChartTitle)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    
                    if dailyChartData.isEmpty {
                        VStack {
                            Text(state.l10n.analyticsChartEmpty)
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
                                    x: .value(state.l10n.analyticsAxisDay, data.dayLabel),
                                    y: .value(state.l10n.analyticsAxisWords, data.words)
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
                
                // Global usage statistics
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.l10n.analyticsDetailed)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    
                    VStack(spacing: 0) {
                        statRow(label: state.l10n.analyticsTotalTranscriptions, value: "\(state.transcriptionHistory.count)")
                        Divider().background(Color(white: 0.95))
                        statRow(label: state.l10n.analyticsAverageLength, value: state.l10n.analyticsWordsValue(Double(state.totalWords) / max(1.0, Double(state.transcriptionHistory.count))))
                        Divider().background(Color(white: 0.95))
                        statRow(label: state.l10n.analyticsPreferredModel, value: state.ollamaModelName)
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

    // Data point backing the SwiftUI Charts view
    struct DailyStat: Identifiable {
        let id = UUID()
        let date: Date
        let words: Int
        /// Locale of the current UI language, so en-US reads MM/dd and it-IT dd/MM.
        let locale: Locale

        var dayLabel: String {
            let formatter = DateFormatter()
            formatter.locale = locale
            // Locale-appropriate day+month ordering rather than a fixed pattern.
            formatter.setLocalizedDateFormatFromTemplate("ddMM")
            return formatter.string(from: date)
        }
    }

    private var dailyChartData: [DailyStat] {
        var groups: [String: (Date, Int)] = [:]
        let calendar = Calendar.current
        
        // Seed the last 7 days with zero
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let key = calendar.startOfDay(for: date).description
                groups[key] = (date, 0)
            }
        }
        
        // Bucket the history into those days
        for record in state.transcriptionHistory {
            let key = calendar.startOfDay(for: record.timestamp).description
            if let val = groups[key] {
                groups[key] = (val.0, val.1 + record.wordCount)
            }
        }
        
        return groups.values
            .map { DailyStat(date: $0.0, words: $0.1, locale: state.uiLanguage.formattingLocale) }
            .sorted(by: { $0.date < $1.date })
    }

    // MARK: - Tab 5: Ollama Monitor

    private var ollamaTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Models resident in RAM/VRAM right now (/api/ps), which is a
                // strict subset of the installed ones (/api/tags).
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(state.l10n.monitorRunningModels)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(white: 0.45))
                        Spacer()
                        Button(action: {
                            NotificationCenter.default.post(name: .mywisprRefreshOllama, object: nil)
                        }) {
                            Text(state.l10n.monitorRefresh)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Color(white: 0.35))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .border(Color(white: 0.8), width: 1)
                        }
                        .buttonStyle(.plain)
                    }

                    if !state.isOllamaConnected {
                        monitorPlaceholder(state.l10n.monitorNotConnected, color: .red)
                    } else if state.loadedOllamaModels.isEmpty {
                        monitorPlaceholder(state.l10n.monitorNoneLoaded, color: .gray)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(state.loadedOllamaModels, id: \.self) { name in
                                HStack {
                                    Image(systemName: "cpu.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                    Text(name)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.black)
                                    Spacer()
                                    Text(state.l10n.monitorInMemory)
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

                // Everything installed on disk, whether or not it is loaded.
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.l10n.monitorInstalled)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))

                    if state.availableOllamaModels.isEmpty {
                        monitorPlaceholder(state.l10n.monitorNoneInstalled, color: .gray)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(state.availableOllamaModels, id: \.self) { name in
                                HStack {
                                    Image(systemName: "internaldrive")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(white: 0.45))
                                    Text(name)
                                        .font(.system(size: 11))
                                        .foregroundColor(.black)
                                    Spacer()
                                    if name == state.ollamaModelName {
                                        Text(state.l10n.monitorInUse)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.black)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                            }
                        }
                        .background(Color.white)
                        .border(Color(white: 0.9), width: 1)
                    }
                }
                
                // Model downloader (pull API)
                VStack(alignment: .leading, spacing: 10) {
                    Text(state.l10n.monitorDownloadSection)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(white: 0.45))
                    
                    Text(state.l10n.monitorDownloadHint)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 12) {
                        TextField(state.l10n.monitorDownloadPlaceholder, text: $pullModelName)
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
                                Text(isPulling ? state.l10n.monitorDownloading : state.l10n.monitorDownload)
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

    /// Routes the picker through `setLanguage` so the glossary swap, persistence
    /// and `SpeechManager` reconfiguration all happen together.
    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { state.dictationLanguage },
            set: { state.setLanguage($0) }
        )
    }

    /// Shared empty/error state box used by the monitor lists.
    private func monitorPlaceholder(_ message: String, color: Color) -> some View {
        Text(message)
            .font(.system(size: 10))
            .foregroundColor(color)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(Color.white)
            .border(Color(white: 0.9), width: 1)
    }

    private func pullModelFromRegistry() {
        guard state.isOllamaConnected else {
            pullStatusMessage = state.l10n.ollamaOfflineCannotPull
            return
        }
        let model = pullModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }

        isPulling = true
        pullStatusMessage = state.l10n.ollamaPullStarted(model)

        ollama.pullModel(model, l10n: state.l10n) { success, message in
            isPulling = false
            pullStatusMessage = message
            if success {
                pullModelName = ""
                // Refresh the installed/loaded model lists
                NotificationCenter.default.post(name: .mywisprRefreshOllama, object: nil)
            }
        }
    }

    // MARK: - Onboarding View
    
    private var onboardingView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(.black)
                
                Text(state.l10n.onboardingWelcome)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                
                Text(state.l10n.onboardingIntro)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.45))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 30)
            
            VStack(spacing: 12) {
                // Step 1: Microphone
                onboardingStep(
                    icon: "mic.fill",
                    title: state.l10n.onboardingMicTitle,
                    description: state.l10n.onboardingMicDesc,
                    granted: state.hasMicrophonePermission,
                    action: {
                        let status = AVCaptureDevice.authorizationStatus(for: .audio)
                        if status == .notDetermined {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                DispatchQueue.main.async {
                                    state.hasMicrophonePermission = granted
                                }
                            }
                        } else {
                            // Already requested once: send the user straight to System Settings
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                )
                
                // Step 2: Speech recognition
                onboardingStep(
                    icon: "brain.head.profile",
                    title: state.l10n.onboardingSpeechTitle,
                    description: state.l10n.onboardingSpeechDesc,
                    granted: state.hasSpeechPermission,
                    action: {
                        let status = SFSpeechRecognizer.authorizationStatus()
                        if status == .notDetermined {
                            SFSpeechRecognizer.requestAuthorization { status in
                                DispatchQueue.main.async {
                                    state.hasSpeechPermission = (status == .authorized)
                                }
                            }
                        } else {
                            // Already requested once: send the user straight to System Settings
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                )
                
                // Step 3: Accessibility — always via System Settings, never the system popup
                //          (the popup can loop forever once TCC has cached a decision)
                onboardingStep(
                    icon: "keyboard.fill",
                    title: state.l10n.onboardingAxTitle,
                    description: state.l10n.onboardingAxDesc,
                    granted: state.hasAccessibilityPermission,
                    action: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            if state.hasMicrophonePermission && state.hasSpeechPermission && state.hasAccessibilityPermission {
                Button(action: {
                    // The onboarding disappears on its own once the polled permission state flips
                }) {
                    Text(state.l10n.onboardingProceed)
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
                VStack(spacing: 8) {
                    Text(state.l10n.onboardingEnableAll)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.orange)
                    
                    Text(state.l10n.onboardingRestartNote)
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                    
                    Button(action: {
                        relaunchApp()
                    }) {
                        Text(state.l10n.onboardingRelaunch)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.white)
                            .border(Color.black, width: 1)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 24)
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
                    Text(state.l10n.onboardingGranted)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green)
                }
            } else {
                Button(action: action) {
                    Text(state.l10n.onboardingGrant)
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

    private func relaunchApp() {
        let path = Bundle.main.bundlePath
        let url = URL(fileURLWithPath: path)
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Bundle Version

extension Bundle {
    /// Short version string from Info.plist, so the UI and the bundle never disagree.
    var appVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }
}
