import SwiftUI
import Supabase

// MARK: - Voice Mode View

/// Full-screen voice conversation interface with dynamic orb visualization
/// Implements advanced turn-taking, barge-in support, and real-time captions
struct VoiceModeView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - State

    @StateObject private var voiceService: GrokVoiceService
    @State private var stateMachine = VoiceStateMachine()

    @State private var showSettings = false
    @State private var showUpgradeSheet = false
    @State private var errorMessage: String?
    @State private var showError = false

    // Emotion analysis setting (persisted) - uses Accelerate/vDSP for fast FFT
    @AppStorage("voiceEmotionAnalysisEnabled") private var emotionAnalysisEnabled = true

    // Transcript state
    @State private var userTranscript = ""
    @State private var assistantTranscript = ""
    @State private var showCaptions = true

    // Animation state
    @State private var isAnimating = false

    // Emotion state
    @State private var showEmotionDetail = false

    // MARK: - Callbacks

    private let onDismiss: (() -> Void)?
    private let onSwitchToText: (() -> Void)?

    // MARK: - Initialization

    init(
        supabase: SupabaseClient,
        onDismiss: (() -> Void)? = nil,
        onSwitchToText: (() -> Void)? = nil
    ) {
        _voiceService = StateObject(wrappedValue: GrokVoiceService(supabase: supabase))
        self.onDismiss = onDismiss
        self.onSwitchToText = onSwitchToText
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                backgroundGradient

                VStack(spacing: 0) {
                    // Top bar with controls
                    topBar
                        .padding(.top, geometry.safeAreaInsets.top > 0 ? 0 : 16)

                    // Usage bar (non-premium only)
                    if !voiceService.isPremium {
                        usageBar
                            .padding(.top, 8)
                    }

                    Spacer()

                    // Captions area
                    if showCaptions {
                        captionsView
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                    }

                    // Central orb
                    orbSection(size: min(geometry.size.width * 0.55, 280))

                    Spacer()

                    // Status text
                    statusView
                        .padding(.bottom, 24)

                    // Bottom controls
                    bottomControls
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 24 : 40)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            VoiceSettingsView(voiceService: voiceService)
        }
        .sheet(isPresented: $showUpgradeSheet) {
            SubscriptionView()
        }
        .sheet(isPresented: $showEmotionDetail) {
            EmotionDetailSheet(
                currentEmotion: voiceService.currentEmotion,
                emotionHistory: voiceService.emotionHistory,
                isPresented: $showEmotionDetail,
                onDisableEmotions: {
                    emotionAnalysisEnabled = false  // Persist the setting
                    voiceService.setEmotionAnalysisEnabled(false)
                }
            )
        }
        .alert("Voice Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
            if shouldShowUpgradeButton {
                Button("Upgrade") {
                    showUpgradeSheet = true
                }
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .task {
            await startVoiceSession()
        }
        .onDisappear {
            Task {
                await endVoiceSession()
            }
        }
        .onChange(of: voiceService.connectionState) { _, newState in
            updateStateMachineFromService(newState)
        }
        .onChange(of: voiceService.isUserSpeaking) { _, isUserSpeaking in
            if isUserSpeaking {
                _ = stateMachine.send(.speechStart)
            } else {
                _ = stateMachine.send(.speechEnd)
            }
        }
        .onChange(of: voiceService.isSpeaking) { _, isSpeaking in
            if isSpeaking {
                _ = stateMachine.send(.serverAudioChunk(Data()))
            } else {
                _ = stateMachine.send(.audioPlaybackFinished)
            }
        }
        .onChange(of: voiceService.transcribedText) { _, newText in
            assistantTranscript = newText
        }
        .onChange(of: voiceService.isIdleDisconnected) { _, isIdleDisconnected in
            if isIdleDisconnected {
                _ = stateMachine.send(.idleTimeoutReached)
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.12),
                Color(red: 0.08, green: 0.08, blue: 0.18),
                Color(red: 0.05, green: 0.05, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Close button
            Button {
                Task {
                    await endVoiceSession()
                    dismiss()
                    onDismiss?()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }

            Spacer()

            // Captions toggle
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showCaptions.toggle()
                }
            } label: {
                Image(systemName: showCaptions ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(showCaptions ? .white : .white.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(showCaptions ? 0.2 : 0.1))
                    .clipShape(Circle())
            }
            .accessibilityLabel(showCaptions ? "Hide captions" : "Show captions")

            // Voice selection
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(voiceColor(voiceService.currentVoice))
                        .frame(width: 10, height: 10)
                    Text(voiceService.currentVoice.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
            .accessibilityLabel("Voice: \(voiceService.currentVoice.displayName). Tap to change.")

            // Settings
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Usage Bar

    private var usageBar: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "clock")
                    .font(.caption)
                Text("Voice Minutes")
                    .font(.caption.weight(.medium))
                Spacer()
                Text("\(String(format: "%.1f", voiceService.minutesRemaining)) / 3 min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white.opacity(0.7))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)

                    Capsule()
                        .fill(usageBarColor)
                        .frame(width: geometry.size.width * usagePercentage, height: 4)
                }
            }
            .frame(height: 4)

            if usagePercentage >= 0.8 {
                Button {
                    showUpgradeSheet = true
                } label: {
                    Text(usagePercentage >= 0.95 ? "Upgrade for Unlimited" : "Running low - Upgrade")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.orange)
                        .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }

    private var usagePercentage: Double {
        let total = 3.0
        let used = total - voiceService.minutesRemaining
        return min(1.0, max(0, used / total))
    }

    private var usageBarColor: Color {
        if usagePercentage >= 0.95 { return .red }
        if usagePercentage >= 0.8 { return .orange }
        return .blue
    }

    // MARK: - Captions View

    private var captionsView: some View {
        VStack(spacing: 12) {
            if !assistantTranscript.isEmpty {
                Text(assistantTranscript)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.1))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.3), value: assistantTranscript)
        .frame(minHeight: 60)
    }

    // MARK: - Orb Section

    private func orbSection(size: CGFloat) -> some View {
        let orbConfig = OrbView.Configuration(
            state: stateMachine.state,
            micLevel: voiceService.micLevel,
            playbackLevel: voiceService.playbackLevel,
            reducedMotion: reduceMotion
        )

        return ZStack {
            OrbContainerView(
                config: orbConfig,
                size: size,
                onTap: {
                    handleOrbTap()
                }
            )

            // Emotion badge overlay (positioned bottom-right of orb)
            // Use emotionHistory.last directly from service instead of duplicate state
            if let snapshot = voiceService.emotionHistory.last {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        EmotionBadge(emotion: snapshot) {
                            showEmotionDetail = true
                        }
                        .offset(x: 8, y: 8)
                    }
                }
                .frame(width: size, height: size)
            }
        }
        .shadow(color: orbShadowColor.opacity(0.4), radius: 40, x: 0, y: 20)
        .animation(.spring(response: 0.4), value: stateMachine.state)
        .animation(.spring(response: 0.3), value: voiceService.emotionHistory.last?.emotion)
    }

    private var orbShadowColor: Color {
        switch stateMachine.state.orbColor {
        case .userSpeaking:
            return .green
        case .aiSpeaking:
            return .blue
        case .thinking:
            return .purple
        case .ready:
            return .blue.opacity(0.6)
        case .error:
            return .red
        default:
            return .gray
        }
    }

    // MARK: - Status View

    private var statusView: some View {
        VStack(spacing: 8) {
            // Connection status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 8, height: 8)

                Text(connectionStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }

            // State status
            Text(stateMachine.state.statusText)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var connectionStatusColor: Color {
        switch voiceService.connectionState {
        case .connected:
            // Check if we're idle disconnected (paused state)
            if voiceService.isIdleDisconnected {
                return .blue.opacity(0.5)
            }
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected:
            // Check if we're in paused state (idle disconnect with mic still listening)
            if voiceService.isIdleDisconnected {
                return .blue.opacity(0.5)
            }
            return .gray
        case .error:
            return .red
        }
    }

    private var connectionStatusText: String {
        switch voiceService.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting..."
        case .reconnecting:
            return "Reconnecting..."
        case .disconnected:
            // Check if we're in paused state
            if voiceService.isIdleDisconnected {
                return "Paused"
            }
            return "Disconnected"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack(spacing: 32) {
            // Mute button
            Button {
                _ = stateMachine.send(.toggleMute)
                if stateMachine.isMuted {
                    voiceService.stopListening()
                } else {
                    try? voiceService.startListening()
                }
            } label: {
                Image(systemName: stateMachine.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(stateMachine.isMuted ? .red : .white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(stateMachine.isMuted ? Color.red.opacity(0.2) : Color.white.opacity(0.15))
                    )
            }
            .accessibilityLabel(stateMachine.isMuted ? "Unmute microphone" : "Mute microphone")

            // End call button
            Button {
                Task {
                    await endVoiceSession()
                    dismiss()
                    onDismiss?()
                }
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(
                        Circle()
                            .fill(Color.red)
                    )
                    .shadow(color: .red.opacity(0.4), radius: 15, x: 0, y: 8)
            }
            .accessibilityLabel("End voice session")

            // Switch to text button
            Button {
                Task {
                    await endVoiceSession()
                    dismiss()
                    onSwitchToText?()
                }
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.15))
                    )
            }
            .accessibilityLabel("Switch to text chat")
        }
    }

    // MARK: - Actions

    private func startVoiceSession() async {
        _ = stateMachine.send(.tapStart)

        // Enable emotion analysis based on user preference
        #if DEBUG
        print("[VoiceMode] Starting with emotionAnalysisEnabled=\(emotionAnalysisEnabled)")
        #endif
        voiceService.setEmotionAnalysisEnabled(emotionAnalysisEnabled)

        do {
            try await voiceService.connect()
            _ = stateMachine.send(.connected)
        } catch let error as VoiceError {
            handleVoiceError(error)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            _ = stateMachine.send(.serverError(error.localizedDescription))
        }
    }

    private func endVoiceSession() async {
        _ = stateMachine.send(.tapEnd)
        await voiceService.disconnect()
    }

    private func handleOrbTap() {
        // Handle tap based on current state
        switch stateMachine.state {
        case .speaking, .thinking, .processing:
            // Manual interrupts disabled - only automatic barge-in via speech detection
            // Tapping during AI speech has no effect
            break

        case .idle:
            // Start session
            Task {
                await startVoiceSession()
            }

        case .idleDisconnected:
            // Tapping while paused triggers reconnection (same as speaking)
            _ = stateMachine.send(.tapStart)

        case .error:
            // Retry connection
            Task {
                await startVoiceSession()
            }

        case .ended:
            // Restart session
            Task {
                await startVoiceSession()
            }

        default:
            break
        }
    }

    private func handleVoiceError(_ error: VoiceError) {
        errorMessage = error.localizedDescription
        showError = true

        if case .quotaExceeded = error {
            _ = stateMachine.send(.quotaExceeded)
            showUpgradeSheet = true
        } else {
            _ = stateMachine.send(.serverError(error.localizedDescription))
        }
    }

    private func updateStateMachineFromService(_ connectionState: GrokVoiceService.ConnectionState) {
        switch connectionState {
        case .connected:
            _ = stateMachine.send(.connected)
        case .connecting:
            // Already in connecting state from tapStart
            break
        case .reconnecting:
            _ = stateMachine.send(.disconnected)
        case .disconnected:
            _ = stateMachine.send(.disconnected)
        case .error(let message):
            _ = stateMachine.send(.serverError(message))
            errorMessage = message
            if message.lowercased().contains("quota") {
                showUpgradeSheet = true
            }
        }
    }

    private var shouldShowUpgradeButton: Bool {
        errorMessage?.lowercased().contains("quota") == true ||
        errorMessage?.lowercased().contains("premium") == true
    }

    private func voiceColor(_ voice: GrokVoice) -> Color {
        switch voice {
        case .ara: return .pink
        case .rex: return .blue
        case .sal: return .purple
        case .eve: return .orange
        case .leo: return .green
        }
    }
}

// MARK: - Preview

#Preview("Voice Mode") {
    VoiceModeView(
        supabase: SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "mock-key"
        )
    )
}
