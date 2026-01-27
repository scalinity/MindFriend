import SwiftUI
import Supabase

// MARK: - Voice Mode View

/// Full-screen voice conversation interface with dynamic orb visualization
/// Implements advanced turn-taking, barge-in support, and real-time captions
struct VoiceModeView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var appState: AppState

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

    // Conversation persistence state
    @State private var userMessages: [String] = []
    @State private var assistantMessages: [String] = []
    @State private var didPersist = false

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
        // Premium gate: Voice mode is premium-only
        if appState.entitlements.tier != .premium {
            VoiceModePaywallView(onUpgrade: {
                appState.showPaywall = true
            }, onDismiss: {
                dismiss()
                onDismiss?()
            })
        } else {
            voiceModeContent
        }
    }

    // MARK: - Voice Mode Content (Premium Only)

    @ViewBuilder
    private var voiceModeContent: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                backgroundGradient

                VStack(spacing: 0) {
                    // Top bar with controls
                    topBar
                        .padding(.top, geometry.safeAreaInsets.top > 0 ? 0 : 16)

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
        .onChange(of: voiceService.isUserSpeaking) { oldValue, isUserSpeaking in
            if isUserSpeaking {
                _ = stateMachine.send(.speechStart)
            } else {
                _ = stateMachine.send(.speechEnd)
            }
        }
        .onChange(of: voiceService.isSpeaking) { oldValue, isSpeaking in
            if isSpeaking {
                _ = stateMachine.send(.serverAudioChunk(Data()))
            } else {
                _ = stateMachine.send(.audioPlaybackFinished)
                // Capture completed assistant response when AI finishes speaking
                if oldValue && !isSpeaking {
                    captureAssistantResponse()
                }
            }
        }
        .onChange(of: voiceService.transcribedText) { _, newText in
            // Only update when there's actual content - don't clear when service resets
            // This preserves the transcript for capture even after response.done clears it
            if !newText.isEmpty {
                assistantTranscript = newText
            }
        }
        .onChange(of: voiceService.userTranscribedText) { oldValue, newText in
            // Capture user message when transcription arrives (async from xAI)
            // This is the only reliable way to get user transcripts since
            // transcription arrives AFTER the user stops speaking
            if !newText.isEmpty && newText != oldValue {
                captureUserMessage(transcript: newText)
            }
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
        // Capture any in-progress transcripts before disconnecting
        // User messages are captured when transcription arrives via onChange,
        // but capture the current one in case it hasn't been processed yet
        let currentUserTranscript = voiceService.userTranscribedText
        if !currentUserTranscript.isEmpty {
            captureUserMessage(transcript: currentUserTranscript)
        }
        captureAssistantResponse()
        await voiceService.disconnect()
        // Persist the conversation to database
        await persistConversation()
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

    // MARK: - Conversation Persistence

    /// Captures a user message from transcription
    /// Called when transcription arrives from xAI (asynchronously after user stops speaking)
    private func captureUserMessage(transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Avoid duplicates - xAI sometimes sends the same transcript multiple times
        if userMessages.last != trimmed {
            userMessages.append(trimmed)
            Log.voice.debug("[VoiceMode] Captured user message: \(trimmed.prefix(50))...")
        }
    }

    /// Captures the current assistant transcript as a completed response
    /// Called when the AI finishes speaking (isSpeaking goes from true to false)
    private func captureAssistantResponse() {
        let trimmed = assistantTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Avoid duplicates
        if assistantMessages.last != trimmed {
            assistantMessages.append(trimmed)
            Log.voice.debug("[VoiceMode] Captured assistant message: \(trimmed.prefix(50))...")
        }
    }

    /// Persists the voice conversation to the database as a text chat
    private func persistConversation() async {
        guard !didPersist else { return }
        didPersist = true

        // Need at least one message to persist
        guard !userMessages.isEmpty || !assistantMessages.isEmpty else {
            Log.voice.debug("[VoiceMode] No messages to persist - userMessages: \(userMessages.count), assistantMessages: \(assistantMessages.count)")
            return
        }

        do {
            // Create a new conversation
            let conversation = try await container.chatService.createConversation()
            Log.voice.debug("[VoiceMode] Created conversation: \(conversation.id)")

            // Interleave user and assistant messages (user speaks, then assistant responds)
            let maxCount = max(userMessages.count, assistantMessages.count)
            for i in 0..<maxCount {
                // User message first (if exists)
                if i < userMessages.count {
                    _ = try await container.chatService.insertMessage(
                        conversationId: conversation.id,
                        role: .user,
                        content: userMessages[i]
                    )
                }
                // Then assistant response (if exists)
                if i < assistantMessages.count {
                    _ = try await container.chatService.insertMessage(
                        conversationId: conversation.id,
                        role: .assistant,
                        content: assistantMessages[i]
                    )
                }
            }
            Log.voice.debug("[VoiceMode] Inserted \(userMessages.count) user + \(assistantMessages.count) assistant messages")

            // Generate a title from the first user message (or assistant if no user messages)
            let titleContent = userMessages.first ?? assistantMessages.first ?? ""
            Log.voice.debug("[VoiceMode] Title content: '\(titleContent.prefix(100))...'")
            if !titleContent.isEmpty {
                do {
                    let generatedTitle = try await container.chatService.generateConversationTitle(
                        conversationId: conversation.id,
                        content: titleContent
                    )
                    Log.voice.debug("[VoiceMode] Generated title: '\(generatedTitle)'")
                } catch {
                    Log.voice.error("[VoiceMode] Title generation failed: \(error)")
                }
            } else {
                Log.voice.warning("[VoiceMode] No content for title generation")
            }

            Log.voice.info("[VoiceMode] Persisted conversation \(conversation.id) with \(userMessages.count) user + \(assistantMessages.count) assistant messages")
        } catch {
            Log.voice.error("[VoiceMode] Failed to persist conversation: \(error)")
            // Don't show error to user - persistence is best-effort
        }
    }
}

// MARK: - Voice Mode Paywall View

/// Paywall view shown to non-premium users when they try to access voice mode
struct VoiceModePaywallView: View {
    let onUpgrade: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dark gradient background matching voice mode
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

            VStack(spacing: 32) {
                Spacer()

                // Voice icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 140, height: 140)

                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .shadow(color: .blue.opacity(0.3), radius: 30, x: 0, y: 10)

                // Title and description
                VStack(spacing: 16) {
                    Text("Voice Mode is Premium")
                        .font(.title.bold())
                        .foregroundStyle(.white)

                    Text("Upgrade to have natural voice conversations with your AI companion. Talk hands-free, get real-time responses, and experience a more personal connection.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Premium features list
                VStack(alignment: .leading, spacing: 12) {
                    PremiumFeatureRow(icon: "mic.fill", text: "Natural voice conversations")
                    PremiumFeatureRow(icon: "person.wave.2.fill", text: "Real-time emotion detection")
                    PremiumFeatureRow(icon: "captions.bubble.fill", text: "Live captions & transcripts")
                    PremiumFeatureRow(icon: "infinity", text: "Unlimited voice minutes")
                }
                .padding(.horizontal, 40)

                Spacer()

                // Action buttons
                VStack(spacing: 16) {
                    Button(action: onUpgrade) {
                        HStack {
                            Image(systemName: "star.fill")
                            Text("Upgrade to Premium")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                    }

                    Button(action: onDismiss) {
                        Text("Maybe Later")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// A single row in the premium features list
private struct PremiumFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
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
    .environmentObject(DependencyContainer.shared)
    .environmentObject(AppState())
}

#Preview("Voice Mode Paywall") {
    VoiceModePaywallView(
        onUpgrade: {},
        onDismiss: {}
    )
}
