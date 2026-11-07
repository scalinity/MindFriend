import SwiftUI
import Supabase

struct VoiceTranscriptDraft: Codable, Equatable {
    let ownerId: UUID
    let conversationId: UUID
    var title: String?
    var messages: [VoiceTranscriptMessage]
}

struct VoiceChatView: View {
    @StateObject private var voiceService: GrokVoiceService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var transcriptDraft: VoiceTranscriptDraft?
    @State private var transcriptOwnerId: UUID?
    @State private var transcriptStorage: SecureStorage?
    @State private var isSavingTranscript = false
    @State private var hasEndedSession = false
    @State private var hasDurableDraft = false
    
    // User message tracking
    @State private var userTranscriptSegments: [String] = []

    // Coordinator to handle voice service events
    @StateObject private var voiceCoordinator: VoiceCoordinator

    init(supabase: SupabaseClient, conversationId: String? = nil) {
        _voiceService = StateObject(wrappedValue: GrokVoiceService(supabase: supabase))
        _voiceCoordinator = StateObject(wrappedValue: VoiceCoordinator())
        _targetConversationId = State(initialValue: conversationId)
        _transcriptOwnerId = State(initialValue: supabase.auth.currentUser?.id)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundGradient

                VStack(spacing: 0) {
                    topBar
                        .padding(.top, geometry.safeAreaInsets.top > 0 ? 0 : 16)

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
            if transcriptDraft != nil && !didPersistTranscript {
                Button("Retry Save") {
                    Task {
                        if await endVoiceSession() { dismiss() }
                    }
                }
                if hasDurableDraft {
                    Button("Close for Now") { dismiss() }
                }
            }
            if shouldShowUpgradeButton {
                Button("Upgrade") {
                    showUpgradeSheet = true
                }
            }
        } message: {
            Text(errorMessage ?? "An error occurred")
        }
        .task {
            guard prepareTranscriptStorage() else { return }
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
                    // Don't overwrite in-progress transcript when text is empty
                    // This happens when the 3-second clear timer fires while audio is still playing
                    guard !text.isEmpty else { return }
                    assistantTranscriptInProgress = trimmedTranscript(
                        from: text,
                        baseline: assistantTranscriptBaseline
                    )
                }
            }

            voiceCoordinator.onUserTranscriptUpdate = { text in
                // Capture user message when transcription arrives from xAI (async)
                // This is the only reliable way to get user transcripts since
                // transcription arrives AFTER the user stops speaking
                captureUserTranscript(text)
            }

            voiceCoordinator.onAssistantSpeechStart = { baselineTranscript in
                assistantTranscriptBaseline = baselineTranscript
                assistantTranscriptInProgress = ""
            }

            voiceCoordinator.onAssistantSpeechEnd = {
                captureAssistantTranscriptIfNeeded()
            }

            // Note: onUserSpeechEnd is no longer used for capturing transcripts
            // because transcription arrives asynchronously after user stops speaking
            
            await startVoiceSession()
        }
        .onDisappear {
            Task { await endVoiceSession() }
        }
        .interactiveDismissDisabled(isSavingTranscript || (transcriptDraft != nil && !hasDurableDraft && !didPersistTranscript))
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task {
                    if await endVoiceSession() { dismiss() }
                }
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
        .padding(.top, 24)
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

            Text("Up to two minutes per session")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
            Text(voiceService.isPremium ? "Unlimited monthly voice minutes" :
                String(format: "%.1f of 3 free monthly voice minutes remaining", voiceService.minutesRemaining))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
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
                    if await endVoiceSession() { dismiss() }
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
            .disabled(isSavingTranscript)
        }
    }

    // MARK: - Actions

    private func startVoiceSession() async {
        guard !hasEndedSession else { return }
        _ = stateMachine.send(.tapStart)
        _ = stateMachine.send(.micPermissionGranted)

        do {
            try await voiceService.connect(startMuted: stateMachine.isMuted)
            _ = stateMachine.send(.connected)
        } catch is CancellationError {
            // Session end and view dismissal already update the connection state.
            return
        } catch let error as VoiceError {
            handleVoiceError(error)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            _ = stateMachine.send(.serverError(error.localizedDescription))
        }
    }

    @discardableResult
    private func endVoiceSession() async -> Bool {
        guard !isSavingTranscript else { return false }
        isSavingTranscript = true
        defer { isSavingTranscript = false }
        hasEndedSession = true
        _ = stateMachine.send(.tapEnd)
        captureUserTranscriptIfNeeded()
        captureAssistantTranscriptIfNeeded()
        await voiceService.disconnect()
        return await persistTranscriptIfNeeded()
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
        // Don't overwrite in-progress transcript when text is empty
        guard !newText.isEmpty else { return }
        assistantTranscriptInProgress = trimmedTranscript(from: newText, baseline: assistantTranscriptBaseline)
    }

    private func captureAssistantTranscriptIfNeeded() {
        let fallback = trimmedTranscript(from: voiceService.transcribedText, baseline: assistantTranscriptBaseline)
        let candidate = assistantTranscriptInProgress.isEmpty ? fallback : assistantTranscriptInProgress
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, assistantTranscriptSegments.last != trimmed {
            assistantTranscriptSegments.append(trimmed)
            appendTranscript(role: "assistant", content: trimmed)
        }
        assistantTranscriptInProgress = ""
        assistantTranscriptBaseline = ""
    }

    /// Captures a user transcript when transcription arrives from xAI (async)
    /// Called when transcription arrives, not when user stops speaking
    private func captureUserTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Avoid duplicates - xAI sometimes sends the same transcript multiple times
        if userTranscriptSegments.last != trimmed {
            userTranscriptSegments.append(trimmed)
            appendTranscript(role: "user", content: trimmed)
        }
    }

    /// Captures the current user transcript from the service (used at end of session)
    private func captureUserTranscriptIfNeeded() {
        // Use the current user transcript from the service
        let transcript = voiceService.userTranscribedText
        if !transcript.isEmpty {
            captureUserTranscript(transcript)
        }
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

    private func prepareTranscriptStorage() -> Bool {
        hasEndedSession = true
        guard let owner = transcriptOwnerId,
              container.supabaseClient.auth.currentUser?.id == owner else {
            errorMessage = "Sign in again before starting voice chat."
            showError = true
            return false
        }
        let key = "voice-transcript.\(owner.uuidString.lowercased())"
        let storage = SecureStorage(keyIdentifier: key)
        transcriptStorage = storage
        do {
            if let draft = try storage.retrieve(forKey: key, as: VoiceTranscriptDraft.self) {
                guard draft.ownerId == owner else {
                    throw SecureStorage.SecureStorageError.invalidData
                }
                transcriptDraft = draft
                targetConversationId = draft.conversationId.uuidString
                hasDurableDraft = true
                hasEndedSession = true
                errorMessage = "A previous voice transcript is saved on this device. Retry saving it to your conversation before starting another session."
                showError = true
                return false
            }
            hasEndedSession = false
            return true
        } catch {
            errorMessage = "Couldn't open your saved voice transcript. Please try again."
            showError = true
            return false
        }
    }

    private func appendTranscript(role: String, content: String) {
        guard !didPersistTranscript, let owner = transcriptOwnerId else { return }
        if transcriptDraft == nil {
            transcriptDraft = VoiceTranscriptDraft(
                ownerId: owner,
                conversationId: targetConversationId.flatMap(UUID.init(uuidString:)) ?? UUID(),
                title: nil,
                messages: []
            )
        }
        if transcriptDraft?.title == nil || (role == "user" && userTranscriptSegments.count == 1) {
            transcriptDraft?.title = String(content.prefix(80))
        }
        transcriptDraft?.messages.append(VoiceTranscriptMessage(
            id: UUID(), role: role, content: content, createdAt: Date()
        ))
        checkpointTranscript()
    }

    private func checkpointTranscript() {
        guard let draft = transcriptDraft, let storage = transcriptStorage else { return }
        do {
            try storage.store(draft, forKey: "voice-transcript.\(draft.ownerId.uuidString.lowercased())")
            hasDurableDraft = true
        } catch {
            hasDurableDraft = false
            errorMessage = "Couldn't keep a local copy of this transcript. Keep this screen open and retry saving when connected."
            showError = true
        }
    }

    private func persistTranscriptIfNeeded() async -> Bool {
        if didPersistTranscript { return true }
        guard let draft = transcriptDraft, !draft.messages.isEmpty else { return true }
        checkpointTranscript()
        guard container.supabaseClient.auth.currentUser?.id == draft.ownerId else {
            errorMessage = "Sign back into the account that started this session to save its transcript."
            showError = true
            return false
        }
        do {
            try await container.chatService.saveVoiceTranscript(
                conversationId: draft.conversationId,
                title: draft.title,
                messages: draft.messages
            )
            guard container.supabaseClient.auth.currentUser?.id == draft.ownerId,
                  transcriptDraft == draft else { return false }
            didPersistTranscript = true
            targetConversationId = draft.conversationId.uuidString
            transcriptStorage?.remove(forKey: "voice-transcript.\(draft.ownerId.uuidString.lowercased())")
            hasDurableDraft = false
            return true
        } catch {
            errorMessage = hasDurableDraft
                ? "Couldn't save this transcript to your conversation. It is kept on this device; retry now or reopen voice chat later."
                : "Couldn't save this transcript. Keep this screen open and retry when connected."
            showError = true
            return false
        }
    }
}
