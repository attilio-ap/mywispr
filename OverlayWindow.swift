import Cocoa
import SwiftUI

// Modificato da NSWindow a NSPanel per poter utilizzare lo stile .nonactivatingPanel.
// Questo consente all'utente di fare click sui bottoni della notch senza che l'applicazione
// diventi attiva in primo piano rubando il focus (cursore) all'applicazione in cui sta scrivendo.
class OverlayWindow: NSPanel {
    let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        
        // Finestra fisica a dimensione fissa (480x60) per evitare tagli del contenuto
        // Utilizziamo il pass-through dei click per rendere cliccabili le aree esterne trasparenti.
        let size = NSSize(width: 480, height: 60)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], // Ignora l'attivazione al click
            backing: .buffered,
            defer: false
        )
        level = .statusBar // Fluttua sopra ogni cosa
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // Rimosso shadow nativo per eliminare ogni traccia di alone rettangolare
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false

        // MARK: - Vibrant glass backing
        // Impostiamo NSVisualEffectView come contentView della finestra.
        // Questo e' il modo corretto su macOS per ottenere la sfocatura del desktop
        // (blendingMode .behindWindow funziona solo se e' la view radice della finestra).
        let vibrantView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        vibrantView.material = .popover
        vibrantView.blendingMode = .behindWindow
        vibrantView.state = .active
        contentView = vibrantView
    }

    /// Posiziona l'overlay centrato sull'asse orizzontale fisico dello schermo principale e sollevato rispetto alla Dock.
    func showCentered() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        
        let w = frame.width
        let h = frame.height
        
        // Centrato esattamente sulla larghezza fisica dello schermo principale
        let x = screenFrame.midX - w / 2
        // Spostato leggermente più in alto (70pt sopra il bordo visibile inferiore/Dock)
        let y = visibleFrame.minY + 70
        
        setFrame(NSRect(x: x, y: y, width: w, height: h), display: true, animate: false)
        orderFrontRegardless()
    }

    /// Calcola se un click è interno alla capsula attiva per il pass-through.
    func isPointInsideCapsule(_ point: NSPoint) -> Bool {
        if appState.showOfflineAlert {
            return checkContains(width: 200, height: 30, point: point)
        }
        
        let mode = appState.overlayMode
        let w: CGFloat
        let h: CGFloat
        
        switch mode {
        case .idle:
            w = 36
            h = 10
        case .hovered:
            w = 300
            h = 30
        case .recording:
            w = appState.partialTranscript.isEmpty ? 140 : 380
            h = 30
        case .processing:
            w = 190
            h = 30
        }
        
        return checkContains(width: w, height: h, point: point)
    }
    
    private func checkContains(width w: CGFloat, height h: CGFloat, point: NSPoint) -> Bool {
        let centerX = frame.width / 2
        let centerY = frame.height / 2
        
        let rect = NSRect(
            x: centerX - w / 2,
            y: centerY - h / 2,
            width: w,
            height: h
        )
        return rect.contains(point)
    }
}

// MARK: - Overlay View

struct OverlayView: View {
    @EnvironmentObject var state: AppState

    private let barCount = 35
    private let silenceThreshold: Float = 0.008

    @State private var barOffsets: [CGFloat] = Array(repeating: 0.5, count: 35)
    @State private var jitterTimer: Timer?
    @State private var processingAnimating = false
    @State private var idlePulse = false
    @State private var isMouseInside = false

    private var isSpeaking: Bool {
        state.audioLevel > silenceThreshold
    }

    private var capsuleWidth: CGFloat {
        if state.showOfflineAlert {
            return 200
        }
        switch state.overlayMode {
        case .idle: return 36
        case .hovered: return 300
        case .recording: return state.partialTranscript.isEmpty ? 140 : 380
        case .processing: return 190
        }
    }

    private var capsuleHeight: CGFloat {
        switch state.overlayMode {
        case .idle: return 10
        default: return 30
        }
    }

    var body: some View {
        ZStack {
            // Ombra manuale per eliminare l'alone nero e dare profondità di Z-depth
            Capsule()
                .fill(Color.black.opacity(0.08))
                .blur(radius: 3)
                .offset(y: 2)
                .frame(width: capsuleWidth, height: capsuleHeight)

            // Capsula principale con effetto Glassmorphism (Vetro sfocato)
            ZStack {
                if state.showOfflineAlert {
                    // Errore offline: leggero tint rosso + bordo rosso
                    Capsule()
                        .fill(Color.red.opacity(0.10))
                        .overlay(
                            Capsule()
                                .stroke(Color.red.opacity(0.45), lineWidth: 1.0)
                        )
                } else {
                    // Vetro puro: il pannello NSVisualEffectView sottostante fornisce la sfocatura.
                    // Qui mettiamo solo un leggerissimo tint bianco satinato + il contorno.
                    Capsule()
                        .fill(Color.white.opacity(0.18))
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.20), lineWidth: 1.0)
                        )
                }

                // Contenuto clippato
                ZStack {
                    if state.showOfflineAlert {
                        offlineAlertView
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    } else {
                        switch state.overlayMode {
                        case .idle:
                            EmptyView()
                            
                        case .hovered:
                            expandedSettingsView
                                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                            
                        case .recording:
                            if !state.partialTranscript.isEmpty {
                                streamingTranscriptView
                                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                            } else if isSpeaking {
                                barsView
                                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                            } else {
                                idleDotsView
                                    .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                            }
                            
                        case .processing:
                            processingView
                                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(width: capsuleWidth, height: capsuleHeight)
            .contentShape(Capsule())
            .onHover { hovering in
                isMouseInside = hovering
                
                guard !state.showOfflineAlert else { return }
                guard state.overlayMode == .idle || state.overlayMode == .hovered else { return }
                
                if hovering {
                    state.overlayMode = .hovered
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if !isMouseInside && state.overlayMode == .hovered {
                            state.overlayMode = .idle
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: state.overlayMode)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: state.partialTranscript)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: state.showOfflineAlert)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onChange(of: state.isRecording) { recording in
            if recording {
                state.overlayMode = .recording
                startJitter()
            } else {
                if !state.isProcessing {
                    state.overlayMode = isMouseInside ? .hovered : .idle
                    stopJitter()
                }
            }
        }
        .onChange(of: state.isProcessing) { processing in
            if processing {
                state.overlayMode = .processing
                stopJitter()
            } else {
                state.overlayMode = isMouseInside ? .hovered : .idle
            }
        }
    }

    // MARK: - Vista di Errore Offline
    private var offlineAlertView: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)
            Text("Ollama Offline - Testo Grezzo")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.red)
        }
    }

    // MARK: - Expanded Settings (Preset Selection)
    private var expandedSettingsView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isOllamaConnected ? Color.green : Color.orange)
                .frame(width: 5, height: 5)
            
            Text(state.aiPreset.displayName.uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
            
            Spacer(minLength: 0)
            
            HStack(spacing: 4) {
                presetButton(preset: .standard, icon: "square.and.pencil")
                presetButton(preset: .professional, icon: "briefcase.fill")
                presetButton(preset: .bullets, icon: "list.bullet")
                presetButton(preset: .englishTranslation, icon: "character.bubble.fill")
                presetButton(preset: .promptBuilder, icon: "lightbulb.fill")
            }
        }
        .padding(.horizontal, 10)
    }

    private func presetButton(preset: AIPreset, icon: String) -> some View {
        let isSelected = state.aiPreset == preset
        return Button(action: {
            state.aiPreset = preset
            let encoder = JSONEncoder()
            if let encoded = try? encoder.encode(preset) {
                UserDefaults.standard.set(encoded, forKey: "mw_preset")
                UserDefaults.standard.synchronize()
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 18, height: 18)
                .background(isSelected ? Color.black : Color.black.opacity(0.06))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trascrizione in Tempo Reale
    private var streamingTranscriptView: some View {
        HStack(spacing: 8) {
            // Indicatore microfono pulsante rosso
            Image(systemName: "mic.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.red)
                .opacity(processingAnimating ? 1.0 : 0.4)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: processingAnimating)
            
            Text(state.partialTranscript)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 12)
        .onAppear {
            processingAnimating = true
        }
        .onDisappear {
            processingAnimating = false
        }
    }

    // MARK: - Equalizzatore Audio
    private var barsView: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.6)
                    .fill(Color.primary)
                    .frame(width: 1.5, height: barHeight(for: i))
            }
        }
        .animation(.interpolatingSpring(stiffness: 380, damping: 15), value: state.audioLevel)
        .animation(.interpolatingSpring(stiffness: 380, damping: 15), value: barOffsets)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = sqrt(CGFloat(state.audioLevel))
        let maxH: CGFloat = 12
        let minH: CGFloat = 2.2
        return max(minH, min(maxH, minH + (maxH - minH) * level * barOffsets[index]))
    }

    // MARK: - Idle Dots
    private var idleDotsView: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 3.0, height: 3.0)
                    .scaleEffect(idlePulse ? 1.0 : 0.6)
                    .opacity(idlePulse ? 0.6 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.8)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.22),
                        value: idlePulse
                    )
            }
        }
    }

    // MARK: - Processing Status
    private var processingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(0.55)
                .frame(width: 12, height: 12)
            
            Text(state.processingStatusText)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Jitter equalizzatore
    private func startJitter() {
        jitterTimer?.invalidate()
        jitterTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in
            DispatchQueue.main.async {
                for i in 0..<barCount {
                    barOffsets[i] = CGFloat.random(in: 0.2...1.0)
                }
            }
        }
    }

    private func stopJitter() {
        jitterTimer?.invalidate()
        jitterTimer = nil
    }
}

// MARK: - Visual Effect View Wrapper (macOS Vibrant Glass)

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
