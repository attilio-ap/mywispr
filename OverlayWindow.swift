import Cocoa
import SwiftUI

/// Floating "Dynamic Island" style overlay shown above every other window.
///
/// Implemented as an `NSPanel` rather than an `NSWindow` so it can use the
/// `.nonactivatingPanel` style: the user can click the buttons inside the notch
/// without MyWispr becoming the active app, which would steal the text cursor
/// from whatever they are currently typing into.
class OverlayWindow: NSPanel {
    let appState: AppState

    /// Transparent padding around the capsule, so shadows and hover tracking
    /// have room to work without being clipped by the window bounds.
    private let capsulePadding: CGFloat = 12

    init(appState: AppState) {
        self.appState = appState

        // Start at the idle size; `updateWindowSize()` keeps it in sync afterwards.
        let capsule = OverlayWindow.capsuleSize(for: .idle, showOfflineAlert: false, partialTranscript: "")
        let size = NSSize(width: capsule.width + 24, height: capsule.height + 24)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
    }

    /// Single source of truth for the capsule geometry.
    ///
    /// Both the SwiftUI view and the window frame derive their size from this,
    /// and `PassThroughHostingView` uses it for hit testing — if these ever
    /// disagreed, clicks would land outside the visible capsule.
    /// Custom preset pills shown in the notch. Beyond this the capsule would grow
    /// wider than is comfortable on screen; the rest stay reachable in the dashboard.
    static let maxCustomPillsInNotch = 3

    static func capsuleSize(for mode: OverlayMode,
                            showOfflineAlert: Bool,
                            partialTranscript: String,
                            customPresetCount: Int = 0) -> NSSize {
        if showOfflineAlert {
            return NSSize(width: 200, height: 30)
        }
        switch mode {
        case .idle:
            return NSSize(width: 36, height: 10)
        case .hovered:
            // Each extra pill is 18pt wide plus 4pt of spacing.
            let pills = min(customPresetCount, maxCustomPillsInNotch)
            return NSSize(width: 300 + CGFloat(pills) * 22, height: 30)
        case .recording:
            // Widen once there is live text to show.
            return NSSize(width: partialTranscript.isEmpty ? 140 : 380, height: 30)
        case .processing:
            return NSSize(width: 190, height: 30)
        }
    }

    /// Places the overlay horizontally centred on the main screen, lifted clear of the Dock.
    func showCentered() {
        updateWindowSize()
        orderFrontRegardless()
    }

    /// Resizes the window to fit the current capsule, keeping it centred.
    func updateWindowSize() {
        guard let screen = NSScreen.main else { return }

        let capsule = OverlayWindow.capsuleSize(
            for: appState.overlayMode,
            showOfflineAlert: appState.showOfflineAlert,
            partialTranscript: appState.partialTranscript,
            customPresetCount: appState.customPresets.count
        )

        let newW = capsule.width + capsulePadding * 2
        let newH = capsule.height + capsulePadding * 2

        let x = screen.frame.midX - newW / 2
        // 70pt above the bottom of the visible area, i.e. clear of the Dock.
        let y = screen.visibleFrame.minY + 70

        setFrame(NSRect(x: x, y: y, width: newW, height: newH), display: true, animate: false)
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

    /// Derived from `OverlayWindow.capsuleSize` so the view and the window can never drift apart.
    private var capsuleSize: NSSize {
        OverlayWindow.capsuleSize(
            for: state.overlayMode,
            showOfflineAlert: state.showOfflineAlert,
            partialTranscript: state.partialTranscript,
            customPresetCount: state.customPresets.count
        )
    }

    var body: some View {
        ZStack {
            // Main capsule — shaped glass
            ZStack {
                if state.showOfflineAlert {
                    // Offline error state
                    Capsule()
                        .fill(.ultraThinMaterial)  // blur clipped to the capsule shape
                        .overlay(
                            Capsule()
                                .fill(Color.red.opacity(0.12))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.red.opacity(0.55), lineWidth: 1.0)
                        )
                } else {
                    // Normal state: Apple-style frosted glass
                    Capsule()
                        .fill(.ultraThinMaterial)  // blur clipped to the capsule shape
                        .overlay(
                            // Defined outer edge — darker than the glass in light
                            // mode, lighter in dark, so it reads as an edge in both.
                            Capsule()
                                .stroke(Theme.label.opacity(0.22), lineWidth: 1.0)
                        )
                        .overlay(
                            // Inner top highlight rim for the 3D glass effect.
                            // A highlight is light in both appearances, so this one
                            // stays white by design.
                            Capsule()
                                .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
                                .padding(0.5)
                        )
                }

                // Clipped content
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
            .frame(width: capsuleSize.width, height: capsuleSize.height)
            .contentShape(Capsule())
            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)  // shadow on the capsule only
            .onHover { hovering in
                isMouseInside = hovering

                guard !state.showOfflineAlert else { return }
                guard state.overlayMode == .idle || state.overlayMode == .hovered else { return }

                if hovering {
                    state.overlayMode = .hovered
                } else {
                    // Small grace period so brushing past the capsule doesn't collapse it instantly.
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

    // MARK: - Offline Error View

    private var offlineAlertView: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)
            Text(state.l10n.overlayOllamaOffline)
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

            Text(state.presetDisplayName(state.l10n).uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                presetButton(preset: .standard, icon: "square.and.pencil")
                presetButton(preset: .professional, icon: "briefcase.fill")
                presetButton(preset: .bullets, icon: "list.bullet")
                presetButton(preset: .translation, icon: "character.bubble.fill")
                presetButton(preset: .promptBuilder, icon: "lightbulb.fill")

                // Custom presets, with the icon chosen when they were created —
                // which until now had no purpose beyond the dashboard list.
                ForEach(state.customPresets.prefix(OverlayWindow.maxCustomPillsInNotch)) { preset in
                    customPresetButton(preset)
                }
            }
        }
        .padding(.horizontal, 10)
    }

    /// A pill for one custom preset. Selected state tracks the active preset by id,
    /// so two custom presets are never both highlighted.
    private func customPresetButton(_ preset: CustomPreset) -> some View {
        let isSelected = state.aiPreset == .custom && state.activeCustomPresetId == preset.id
        return Button(action: {
            state.activateCustomPreset(id: preset.id)
        }) {
            Image(systemName: preset.icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(isSelected ? Theme.onAccent : Theme.label)
                .frame(width: 18, height: 18)
                .background(isSelected ? Theme.accent : Theme.accentMuted)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func presetButton(preset: AIPreset, icon: String) -> some View {
        let isSelected = state.aiPreset == preset && state.activeCustomPresetId == nil
        return Button(action: {
            state.aiPreset = preset
            state.activeCustomPresetId = nil
            state.persistData()
        }) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(isSelected ? Theme.onAccent : Theme.label)
                .frame(width: 18, height: 18)
                .background(isSelected ? Theme.accent : Theme.accentMuted)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live Transcript

    private var streamingTranscriptView: some View {
        HStack(spacing: 8) {
            // Pulsing red microphone indicator
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

    // MARK: - Audio Equaliser

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
        // sqrt() compresses the dynamic range so quiet speech still moves the bars.
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

    // MARK: - Equaliser Jitter

    /// The microphone only gives us one overall level, so each bar gets a random
    /// multiplier refreshed a few times a second to make the equaliser feel alive.
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
