import SwiftUI
import Supabase

struct VoiceChatView: View {
    @StateObject private var voiceService: GrokVoiceService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var container: DependencyContainer

    @State private var stateMachine = VoiceStateMachine()
    @State private var showSettings = false
    @State private var showUpgradeSheet = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var targetConversationId: String?
    @State private var assistantTranscriptSegments: [String] = []
    @State private var assistantTranscriptBaseline = ""
    @State private var assistantTranscriptInProgress = ""
    @State private var didPersistTranscript = false
    
    // Coordinator to handle voice service events
    @StateObject private var voiceCoordinator: VoiceCoordinator

    init(supabase: SupabaseClient, conversationId: String? = nil) {
        _voiceService = StateObject(wrappedValue: GrokVoiceService(supabase: supabase))
        _voiceCoordinator = StateObject(wrappedValue: VoiceCoordinator())
        _targetConversationId = State(initialValue: conversationId)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient

                VStack(spacing: 0) {
                    topBar
                        .padding(.top, geometry.safeAreaInsets.top > 0 ? 0 : 16)

                    if !voiceService.isPremium {
                        usageBar
                            .padding(.top, 8)
                    }

                    Spacer()

                    if stateMachine.captionsEnabled {
                        captionsView
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                    }

                    orbSection(size: min(geometry.size.width * 0.56, 300))

                    Spacer()

                    statusView
                        .padding(.bottom, 24)

                    bottomControls
                        .padding(.horizontal, 32)
                        .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 28 : 40)
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
            // Configure coordinator callbacks
            voiceCoordinator.onStateEvent = { event in
                _ = stateMachine.send(event)
            }
            voiceService.delegate = voiceCoordinator

            // Set up coordinator callbacks
            voiceCoordinator.onError = { message in
                errorMessage = message
                showError = true
            }

            voiceCoordinator.onQuotaExceeded = {
                showUpgradeSheet = true
            }

            voiceCoordinator.onTranscriptUpdate = { text in
                if voiceService.isSpeaking {
                    assistantTranscriptInProgress = trimmedTranscript(
                        from: text,
                        baseline: assistantTranscriptBaseline
                    )
                }
            }

            voiceCoordinator.onAssistantSpeechStart = { baselineTranscript in
                assistantTranscriptBaseline = baselineTranscript
                assistantTranscriptInProgress = ""
            }

            voiceCoordinator.onAssistantSpeechEnd = {
                captureAssistantTranscriptIfNeeded()
            }
            
            await startVoiceSession()
        }
        .onDisappear {
            Task {
                await endVoiceSession()
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.12),
                Color(red: 0.08, green: 0.08, blue: 0.18),
                Color(red: 0.05, green: 0.05, blue: 0.12),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Spacer()

            Button {
                _ = stateMachine.send(.toggleCaptions)
            } label: {
                Image(systemName: stateMachine.captionsEnabled ? "captions.bubble.fill" : "captions.bubble")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(stateMachine.captionsEnabled ? .white : .white.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(stateMachine.captionsEnabled ? 0.2 : 0.1))
                    .clipShape(Circle())
            }
            .accessibilityLabel(stateMachine.captionsEnabled ? "Hide captions" : "Show captions")

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

    // MARK: - Captions

    private var captionsView: some View {
        VStack(spacing: 12) {
            if !voiceService.transcribedText.isEmpty {
                Text(voiceService.transcribedText)
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
        .animation(.spring(response: 0.3), value: voiceService.transcribedText)
        .frame(minHeight: 60)
    }

    // MARK: - Orb

    private func orbSection(size: CGFloat) -> some View {
        let config = OrbView.Configuration(
            state: stateMachine.state,
            micLevel: voiceService.micLevel,
            playbackLevel: voiceService.playbackLevel,
            reducedMotion: reduceMotion
        )

        return OrbContainerView(config: config, size: size) {
            handleOrbTap()
        }
        .shadow(color: orbShadowColor.opacity(0.4), radius: 40, x: 0, y: 20)
        .animation(.spring(response: 0.4), value: stateMachine.state)
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

    // MARK: - Status

    private var statusView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 8, height: 8)

                Text(connectionStatusText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Text(stateMachine.state.statusText)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var connectionStatusColor: Color {
        switch voiceService.connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .disconnected:
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
            return "Disconnected"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    // MARK: - Controls

    private var bottomControls: some View {
        HStack {
            Button {
                _ = stateMachine.send(.toggleMute)
                if stateMachine.isMuted {
                    voiceService.stopListening()
                } else {
                    do {
                        try voiceService.startListening()
                    } catch {
                        errorMessage = error.localizedDescription
                        showError = true
                    }
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

            Spacer()

            Button {
                Task {
                    await endVoiceSession()
                    dismiss()
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
        }
    }

    // MARK: - Actions

    private func startVoiceSession() async {
        _ = stateMachine.send(.tapStart)
        _ = stateMachine.send(.micPermissionGranted)

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
        captureAssistantTranscriptIfNeeded()
        let transcriptText = buildTranscriptText()
        await voiceService.disconnect()
        await persistTranscriptIfNeeded(transcriptText)
    }

    private func handleOrbTap() {
        switch stateMachine.state {
        case .speaking, .thinking, .processing:
            _ = stateMachine.send(.tapInterrupt)
            voiceService.interruptPlayback()
        case .idle, .error:
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

        switch error {
        case .quotaExceeded:
            _ = stateMachine.send(.quotaExceeded)
            showUpgradeSheet = true
        case .microphonePermissionDenied:
            _ = stateMachine.send(.micPermissionDenied)
        default:
            _ = stateMachine.send(.serverError(error.localizedDescription))
        }
    }

    private func updateStateMachineFromService(_ connectionState: GrokVoiceService.ConnectionState) {
        switch connectionState {
        case .connected:
            _ = stateMachine.send(.connected)
        case .connecting:
            break
        case .reconnecting, .disconnected:
            _ = stateMachine.send(.disconnected)
        case .error(let message):
            _ = stateMachine.send(.serverError(message))
            errorMessage = message
            if message.lowercased().contains("quota") {
                showUpgradeSheet = true
            }
        }
    }

    private func handleUserSpeechChange(_ isSpeaking: Bool) {
        if isSpeaking {
            _ = stateMachine.send(.speechStart)
        } else {
            _ = stateMachine.send(.speechEnd)
            _ = stateMachine.send(.serverThinking)
        }
    }

    private func handleAssistantSpeechChange(_ isSpeaking: Bool) {
        if isSpeaking {
            assistantTranscriptBaseline = voiceService.transcribedText
            assistantTranscriptInProgress = ""
            _ = stateMachine.send(.serverAudioChunk(Data()))
        } else {
            captureAssistantTranscriptIfNeeded()
            _ = stateMachine.send(.audioPlaybackFinished)
        }
    }

    private func handleTranscriptUpdate(_ newText: String) {
        guard voiceService.isSpeaking else { return }
        assistantTranscriptInProgress = trimmedTranscript(from: newText, baseline: assistantTranscriptBaseline)
    }

    private func captureAssistantTranscriptIfNeeded() {
        let fallback = trimmedTranscript(from: voiceService.transcribedText, baseline: assistantTranscriptBaseline)
        let candidate = assistantTranscriptInProgress.isEmpty ? fallback : assistantTranscriptInProgress
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, assistantTranscriptSegments.last != trimmed {
            assistantTranscriptSegments.append(trimmed)
        }
        assistantTranscriptInProgress = ""
        assistantTranscriptBaseline = ""
    }

    private func trimmedTranscript(from text: String, baseline: String) -> String {
        let rawText = text
        guard !rawText.isEmpty else { return "" }
        if !baseline.isEmpty, rawText.hasPrefix(baseline) {
            let startIndex = rawText.index(rawText.startIndex, offsetBy: baseline.count)
            return String(rawText[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func buildTranscriptText() -> String {
        var segments = assistantTranscriptSegments
        let pending = trimmedTranscript(from: assistantTranscriptInProgress, baseline: "")
        if !pending.isEmpty, segments.last != pending {
            segments.append(pending)
        }
        let cleaned = segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        if cleaned.count == 1 {
            return cleaned[0]
        }
        let body = cleaned.joined(separator: "\n\n")
        return "Voice session transcript:\n\n\(body)"
    }

    private func persistTranscriptIfNeeded(_ transcriptText: String) async {
        guard !didPersistTranscript else { return }
        didPersistTranscript = true
        let trimmed = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            if targetConversationId == nil {
                let conversation = try await container.chatService.createConversation()
                targetConversationId = conversation.id
            }
            guard let conversationId = targetConversationId else { return }
            _ = try await container.chatService.insertMessage(
                conversationId: conversationId,
                role: .assistant,
                content: trimmed
            )

            // Generate a title for the conversation based on the transcript
            _ = try await container.chatService.generateConversationTitle(
                conversationId: conversationId,
                content: trimmed
            )
        } catch {
            errorMessage = "Couldn't save transcript. \(error.localizedDescription)"
            showError = true
        }
    }
}
