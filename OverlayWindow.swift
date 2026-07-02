import Cocoa
import SwiftUI

// Modificato da NSWindow a NSPanel per poter utilizzare lo stile .nonactivatingPanel.
// Questo consente all'utente di fare click sui bottoni della notch senza che l'applicazione
// diventi attiva in primo piano rubando il focus (cursore) all'applicazione in cui sta scrivendo.
class OverlayWindow: NSPanel {
    let appState: AppState
    
    init(appState: AppState) {
        self.appState = appState
        
        // Finestra fisica a dimensione fissa (320x50) per evitare rallentamenti nel ridimensionamento del WindowServer.
        // Utilizziamo il pass-through dei click per rendere cliccabili le aree esterne trasparenti.
        let size = NSSize(width: 320, height: 50)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], // Aggiunto .nonactivatingPanel per ignorare l'attivazione al click
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
        let mode = appState.overlayMode
        let w: CGFloat
        let h: CGFloat
        
        switch mode {
        case .idle:
            w = 36
            h = 10
        case .hovered:
            w = 300
            h = 28
        case .recording:
            w = 140
            h = 28
        case .processing:
            w = 90
            h = 28
        }
        
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
        switch state.overlayMode {
        case .idle: return 36
        case .hovered: return 300
        case .recording: return 140
        case .processing: return 90
        }
    }

    private var capsuleHeight: CGFloat {
        switch state.overlayMode {
        case .idle: return 10
        default: return 28
        }
    }

    var body: some View {
        // La capsula viene posizionata al centro del contenitore trasparente infinito
        ZStack {
            // Ombra manuale posizionata dietro la capsula
            Capsule()
                .fill(Color.black.opacity(0.35))
                .blur(radius: 4)
                .offset(y: 2.5)
                .frame(width: capsuleWidth, height: capsuleHeight)

            // Capsula principale di sfondo e contenuto
            ZStack {
                Capsule()
                    .fill(Color.black)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.45), lineWidth: 0.6)
                    )

                // Contenuto clippato alla forma della capsula
                ZStack {
                    switch state.overlayMode {
                    case .idle:
                        EmptyView()
                        
                    case .hovered:
                        expandedSettingsView
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                        
                    case .recording:
                        if isSpeaking {
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
                .clipShape(Capsule())
            }
            .frame(width: capsuleWidth, height: capsuleHeight)
            .contentShape(Capsule()) // Definisce l'area esatta di interazione per mouse-hover e click
            .onHover { hovering in
                isMouseInside = hovering
                
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
        // Animazione fluida applicata esclusivamente alle dimensioni della capsula
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: state.overlayMode)
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

    // MARK: - Expanded Settings (Preset Selection)

    private var expandedSettingsView: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isOllamaConnected ? Color.green : Color.orange)
                .frame(width: 5, height: 5)
            
            Text(state.aiPreset.displayName.uppercased())
                .font(.custom("Helvetica", size: 8))
                .fontWeight(.black)
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)
            
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
                .foregroundColor(isSelected ? .black : .white)
                .frame(width: 17, height: 17)
                .background(isSelected ? Color.white : Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Equalizzatore Audio

    private var barsView: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 0.6)
                    .fill(Color.white)
                    .shadow(color: Color.white.opacity(0.35), radius: 1, x: 0, y: 0)
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
                    .fill(Color.white.opacity(0.35))
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

    // MARK: - Processing Dots

    private var processingView: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .shadow(color: Color.white.opacity(0.4), radius: 1.5, x: 0, y: 0)
                    .frame(width: 3.5, height: 3.5)
                    .scaleEffect(processingAnimating ? 1.15 : 0.45)
                    .opacity(processingAnimating ? 0.95 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.12),
                        value: processingAnimating
                    )
            }
        }
        .onAppear {
            processingAnimating = true
        }
        .onDisappear {
            processingAnimating = false
        }
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
