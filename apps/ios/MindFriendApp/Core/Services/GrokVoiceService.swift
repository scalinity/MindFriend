import Foundation
import AVFoundation
import Combine
import Supabase
import OSLog

/// Service for real-time voice conversations using Grok Voice Agent API
@MainActor
final class GrokVoiceService: ObservableObject, VoiceServiceProtocol {

    // MARK: - Type Aliases
    
    /// Backward compatibility: existing code uses GrokVoiceService.ConnectionState
    typealias ConnectionState = VoiceConnectionState

    // MARK: - Published Properties

    @Published private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            delegate?.voiceService(self, didEmit: .connectionStateChanged(connectionState))
        }
    }
    @Published private(set) var isListening = false {
        didSet {
            if isListening && !oldValue {
                delegate?.voiceService(self, didEmit: .listeningStarted)
            } else if !isListening && oldValue {
                delegate?.voiceService(self, didEmit: .listeningEnded)
            }
        }
    }
    @Published private(set) var isSpeaking = false {
        didSet {
            if isSpeaking && !oldValue {
                delegate?.voiceService(self, didEmit: .assistantSpeechStarted)
            } else if !isSpeaking && oldValue {
                delegate?.voiceService(self, didEmit: .assistantSpeechEnded)
            }
        }
    }
    @Published private(set) var isUserSpeaking = false {
        didSet {
            if isUserSpeaking && !oldValue {
                delegate?.voiceService(self, didEmit: .userSpeechStarted)
            } else if !isUserSpeaking && oldValue {
                delegate?.voiceService(self, didEmit: .userSpeechEnded)
            }
        }
    }
    @Published private(set) var transcribedText = "" {
        didSet {
            if transcribedText != oldValue {
                delegate?.voiceService(self, didEmit: .transcriptUpdated(transcribedText))
            }
        }
    }
    
    /// Transcribed text of user's speech (from input audio transcription)
    @Published private(set) var userTranscribedText = "" {
        didSet {
            if userTranscribedText != oldValue {
                delegate?.voiceService(self, didEmit: .userTranscriptUpdated(userTranscribedText))
            }
        }
    }
    
    @Published private(set) var minutesRemaining: Double = 0 {
        didSet {
            if minutesRemaining != oldValue {
                delegate?.voiceService(self, didEmit: .quotaUpdated(minutesRemaining))
            }
        }
    }
    @Published private(set) var currentVoice: GrokVoice = .ara
    @Published private(set) var availableVoices: [GrokVoice] = [.ara]

    /// Smoothed microphone input level (0.0 - 1.0) for orb visualization
    @Published private(set) var micLevel: Float = 0

    /// Smoothed playback output level (0.0 - 1.0) for orb visualization
    @Published private(set) var playbackLevel: Float = 0

    @Published private(set) var isPremium = false {
        didSet {
            // Stop usage timer when user upgrades to premium (unlimited quota)
            if isPremium && !oldValue {
                stopUsageTimer()
            }
        }
    }

    /// Retained for voice UI compatibility; relay session ends stop microphone capture.
    @Published private(set) var isIdleDisconnected = false {
        didSet {
            if isIdleDisconnected && !oldValue {
                delegate?.voiceService(self, didEmit: .idleDisconnected)
            }
        }
    }

    // MARK: - Emotion State

    /// Current detected emotion (nil if no emotion detected or analysis disabled)
    @Published private(set) var currentEmotion: EmotionResult?

    /// Emotion history for current session
    @Published private(set) var emotionHistory: [EmotionSnapshot] = []

    /// Confidence score for current emotion (0.0 - 1.0)
    @Published private(set) var emotionConfidence: Double = 0

    // MARK: - Delegate

    weak var delegate: VoiceServiceDelegate?

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    
    // Specialized components
    private let webSocketManager = VoiceWebSocketManager()
    private let audioCapture = VoiceAudioCapture()
    private let audioPlayback = VoiceAudioPlayback()

    // Emotion analysis
    private let emotionAnalyzer = EmotionAnalyzer()
    // Emotion analysis enabled by default - uses Accelerate/vDSP for fast FFT
    private var emotionAnalysisEnabled: Bool = UserDefaults.standard.object(forKey: "voiceEmotionAnalysisEnabled") as? Bool ?? false
    private var emotionSensitivityThreshold: Double = 0.6
    private var lastEmotionAnalysisTime: Date?
    private let emotionAnalysisCooldown: TimeInterval = 2.0  // Min 2s between analyses
    private var emotionAnalysisTask: Task<Void, Never>?
    private let maxEmotionHistorySize = 100  // Cap history at ~3 minutes at 2s intervals

    // Session tracking
    private var connectionGeneration = UUID()
    private var isDisconnecting = false
    private var lifecycleSubscriptions = Set<AnyCancellable>()
    private var sessionId: String?
    private var sessionStartTime: Date?
    private var initialMinutesRemaining: Double = 0
    private var messageCount = 0
    private var didReceiveSessionCreated = false
    private var didReceiveSessionUpdated = false
    private var sessionCreatedContinuation: CheckedContinuation<Void, Error>?
    private var sessionUpdatedContinuation: CheckedContinuation<Void, Error>?
    private var sessionCreatedTimeoutTask: Task<Void, Never>?
    private var sessionUpdatedTimeoutTask: Task<Void, Never>?
    private var isWaitingForResponse = false
    private var usageTimer: Timer?
    private var sessionLimitTask: Task<Void, Never>?
    private let sessionLimitMessage = "Voice session ended. Sessions last up to two minutes, or your remaining monthly allowance. Tap to start a new session."

    // MARK: - Idle Management

    /// Timer that checks for idle state and disconnects WebSocket
    private var idleDisconnectTimer: Timer?

    /// Last time speech activity was detected
    private var lastSpeechActivityTime: Date?

    /// Threshold in seconds before idle disconnect (90 seconds)
    private let idleDisconnectThreshold: TimeInterval = 90

    // Voice instructions for MindFriend personality
    private let voiceInstructions = """
    You are a warm, supportive AI companion for MindFriend, a mental wellness app.

    IMPORTANT: You have access to real-time voice emotion detection. The app analyzes the user's tone of voice and may provide emotion context (like "[Detected emotion: sad]") in system messages. When you see this:
    - Acknowledge and validate the detected emotion naturally
    - Tailor your response to match their emotional state
    - Don't explicitly say "I detected you're feeling X" - instead respond with appropriate empathy

    Guidelines:
    - Be empathetic, understanding, and non-judgmental
    - Use a conversational, friendly tone
    - Ask follow-up questions to understand feelings better
    - Offer gentle suggestions without being prescriptive
    - If user expresses self-harm or crisis, immediately provide crisis resources and the number 988
    - Keep responses concise for voice (2-3 sentences typically)
    - Acknowledge emotions before offering perspectives
    - Never diagnose or provide medical advice
    """

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
        setupComponentCallbacks()
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                Task { @MainActor in
                    self?.finishSession(message: "Audio was interrupted. Tap to start a new voice session.")
                }
            }.store(in: &lifecycleSubscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
                Task { @MainActor in
                    self?.finishSession(message: "Audio device disconnected. Tap to start a new voice session.")
                }
            }.store(in: &lifecycleSubscriptions)

        // Grant consent if user previously enabled emotion analysis (persisted in UserDefaults)
        // This respects the user's previous opt-in choice
        if emotionAnalysisEnabled {
            emotionAnalyzer.setVoiceConsent(true)
            audioCapture.emotionBufferEnabled = true
            #if DEBUG
            print("[GrokVoiceService] Init: emotion analysis enabled from UserDefaults, consent granted")
            #endif
        }
    }
    
    private func setupComponentCallbacks() {
        // WebSocket callbacks
        webSocketManager.onMessage = { [weak self] message in
            self?.handleWebSocketMessage(message)
        }
        
        webSocketManager.onConnectionLost = { [weak self] reachedLimit in
            guard let self else { return }
            self.finishSession(message: reachedLimit ? self.sessionLimitMessage :
                "Connection lost. Tap to start a new voice session.")
        }

        // Audio capture callbacks
        audioCapture.onAudioData = { [weak self] audioData in
            Task { @MainActor in
                self?.sendAudioData(audioData)
            }
        }

        audioCapture.onMicLevelUpdate = { [weak self] level in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                self.micLevel = level
            }
        }

        // Audio playback callbacks
        audioPlayback.onPlaybackStart = { [weak self] in
            Task { @MainActor in
                guard let self, self.connectionState.isConnected else { return }
                self.isSpeaking = true
            }
        }
        
        audioPlayback.onPlaybackEnd = { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = false
            }
        }
        
        audioPlayback.onPlaybackLevelUpdate = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.playbackLevel = self.isSpeaking ? level : 0
            }
        }
    }

    // MARK: - Public Methods

    /// Connect to voice service
    func connect() async throws {
        try await connect(startMuted: false)
    }

    func connect(startMuted: Bool) async throws {
        guard !isDisconnecting else {
            throw VoiceError.connectionFailed("The previous voice session is ending. Try again shortly.")
        }
        guard connectionState != .connected && connectionState != .connecting else { return }

        connectionState = .connecting
        let generation = UUID()
        connectionGeneration = generation

        // Every explicit connection starts a new relay session.
        isIdleDisconnected = false

        do {
            try await requestMicrophonePermission()
            try Task.checkCancellation()
            guard connectionGeneration == generation else { throw CancellationError() }

            let tokenResponse = try await fetchVoiceToken()
            guard !Task.isCancelled, connectionGeneration == generation else {
                // This response belongs to an obsolete attempt, never the active session.
                // A new task lets the compensating request run even if connect was cancelled.
                await Task { @MainActor in
                    await endSession(sessionId: tokenResponse.sessionId, durationSeconds: 0, messagesCount: 0)
                }.value
                throw CancellationError()
            }

            minutesRemaining = tokenResponse.minutesRemaining
            initialMinutesRemaining = tokenResponse.minutesRemaining
            isPremium = tokenResponse.isPremium
            availableVoices = tokenResponse.grokAvailableVoices
            currentVoice = tokenResponse.grokVoice
            sessionId = tokenResponse.sessionId
            sessionStartTime = Date()

            guard let duration = tokenResponse.relayDurationSeconds else {
                throw VoiceError.connectionFailed("Secure voice relay is unavailable. A compatible app and voice server are required.")
            }
            // Secondary client cap. The relay enforces the authoritative session limit.
            sessionLimitTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000) }
                catch { return }
                guard let self, self.connectionGeneration == generation else { return }
                self.finishSession(message: self.sessionLimitMessage)
            }
            let userSession = try await supabase.auth.session
            try Task.checkCancellation()
            guard connectionGeneration == generation else { throw CancellationError() }
            didReceiveSessionCreated = false
            try await webSocketManager.connect(sessionId: tokenResponse.sessionId, userToken: userSession.accessToken)
            try Task.checkCancellation()
            guard connectionGeneration == generation else { throw CancellationError() }

            // Wait for session.created event from the server
            #if DEBUG
            Log.voice.debug("[Voice] Waiting for session.created event...")
            #endif
            if !didReceiveSessionCreated {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sessionCreatedContinuation = continuation

                // Set timeout for session creation - store task to cancel if event arrives
                sessionCreatedTimeoutTask = Task { @MainActor [weak self] in
                    // Relay preparation and socket setup each allow twelve seconds.
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard let self, !Task.isCancelled else { return }
                    if let cont = self.sessionCreatedContinuation {
                        self.sessionCreatedContinuation = nil
                        cont.resume(throwing: VoiceError.connectionTimeout)
                    }
                }
            }

            }
            // Now configure the session with our settings
            try Task.checkCancellation()
            guard connectionGeneration == generation else { throw CancellationError() }
            didReceiveSessionUpdated = false
            try await configureSession()
            try Task.checkCancellation()
            guard connectionGeneration == generation else { throw CancellationError() }

            // Wait for session.updated confirmation
            #if DEBUG
            Log.voice.debug("[Voice] Waiting for session.updated...")
            #endif
            if !didReceiveSessionUpdated {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sessionUpdatedContinuation = continuation

                // Set timeout - store task to cancel if event arrives
                sessionUpdatedTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard let self, !Task.isCancelled else { return }
                    if let cont = self.sessionUpdatedContinuation {
                        self.sessionUpdatedContinuation = nil
                        cont.resume(throwing: VoiceError.connectionTimeout)
                    }
                }
            }

            }
            try Task.checkCancellation()
            guard connectionGeneration == generation else { throw CancellationError() }
            connectionState = .connected
            messageCount = 0
            #if DEBUG
            Log.voice.debug("[Voice] Connection complete, ready for audio")
            #endif

            // Start live usage timer for non-premium users
            if !isPremium {
                startUsageTimer()
            }

            // Start idle disconnect timer
            startIdleTimer()

            // Preserve the microphone choice when explicitly starting a new session.
            if !startMuted { try startListening() }
        } catch {
            if connectionGeneration == generation {
                await disconnect()
                if !(error is CancellationError) { connectionState = .error(error.localizedDescription) }
            }
            throw error
        }
    }

    /// Disconnect from voice service
    func disconnect() async {
        await disconnect(endingState: .disconnected)
    }

    private func disconnect(endingState: ConnectionState) async {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        connectionGeneration = UUID()
        defer { isDisconnecting = false }
        stopListening()
        audioPlayback.stop()
        isSpeaking = false
        isUserSpeaking = false
        micLevel = 0
        playbackLevel = 0
        stopUsageTimer()
        sessionLimitTask?.cancel()
        sessionLimitTask = nil
        stopIdleTimer()

        // Cancel emotion analysis task
        emotionAnalysisTask?.cancel()
        emotionAnalysisTask = nil

        // Cancel any pending timeout tasks first
        sessionCreatedTimeoutTask?.cancel()
        sessionCreatedTimeoutTask = nil
        sessionUpdatedTimeoutTask?.cancel()
        sessionUpdatedTimeoutTask = nil

        // Cancel any pending continuations
        if let continuation = sessionCreatedContinuation {
            sessionCreatedContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        if let continuation = sessionUpdatedContinuation {
            sessionUpdatedContinuation = nil
            continuation.resume(throwing: CancellationError())
        }

        webSocketManager.disconnect()

        let endedSessionId = sessionId
        let elapsedSeconds = max(0, Date().timeIntervalSince(sessionStartTime ?? Date()))
        let durationSeconds = Int(elapsedSeconds)
        if !isPremium { minutesRemaining = max(0, initialMinutesRemaining - elapsedSeconds / 60) }
        let endedMessageCount = messageCount
        sessionId = nil
        sessionStartTime = nil
        connectionState = endingState
        transcribedText = ""
        isWaitingForResponse = false

        // Clear idle state
        isIdleDisconnected = false
        lastSpeechActivityTime = nil

        // Clear echo suppression state
        playbackStartTime = nil
        echoGateFramesAboveThreshold = 0
        echoGateFramesBelowThreshold = 0

        // Clear emotion state
        currentEmotion = nil
        emotionConfidence = 0
        emotionHistory = []
        lastEmotionAnalysisTime = nil
        audioCapture.clearRollingBuffer()

        if let endedSessionId {
            await endSession(sessionId: endedSessionId, durationSeconds: durationSeconds, messagesCount: endedMessageCount)
        }
    }

    private func finishSession(message: String) {
        guard !isDisconnecting, connectionState != .disconnected else { return }
        let generation = connectionGeneration
        Task { @MainActor [weak self] in
            guard let self, self.connectionGeneration == generation else { return }
            await self.disconnect(endingState: .error(message))
        }
    }

    /// Start listening for voice input
    func startListening() throws {
        #if DEBUG
        Log.voice.debug("[Voice] startListening called, connectionState: \(self.connectionState)")
        #endif
        guard connectionState.isConnected else {
            #if DEBUG
            Log.voice.debug("[Voice] Not connected, cannot start listening")
            #endif
            throw VoiceError.notConnected
        }

        guard !isListening else {
            #if DEBUG
            Log.voice.debug("[Voice] Already listening, skipping")
            #endif
            return
        }

        try audioCapture.startCapture()
        isListening = true
        
        #if DEBUG
        Log.voice.debug("[Voice] Now listening for audio input")
        #endif
    }

    /// Force commit audio buffer and get response (for edge cases when VAD doesn't trigger)
    /// With server_vad enabled, the server will auto-respond after commit
    func stopListeningAndRespond() {
        guard connectionState.isConnected else {
            #if DEBUG
            Log.voice.debug("[Voice] Not connected, cannot send")
            #endif
            return
        }

        guard !isWaitingForResponse else {
            #if DEBUG
            Log.voice.debug("[Voice] Already waiting for response, ignoring")
            #endif
            return
        }

        #if DEBUG
        Log.voice.debug("[Voice] Force commit (turn \(self.messageCount + 1))...")
        #endif
        isWaitingForResponse = true
        transcribedText = ""

        // Just commit - with server_vad + create_response: true, server will auto-respond
        webSocketManager.send(["type": "input_audio_buffer.commit"])

        // Note: We don't stop listening or send response.create
        // The server handles everything after commit
        // Audio capture continues for the next turn
    }

    /// Interrupt assistant playback immediately for barge-in.
    /// This stops audio, cancels any pending server response, and prepares for user input.
    func interruptPlayback() {
        guard connectionState.isConnected else { return }

        // Check if there's actually something to interrupt
        let wasPlaying = isSpeaking || isWaitingForResponse
        guard wasPlaying else { return }

        #if DEBUG
        Log.voice.debug("[Voice] Barge-in: interrupting playback")
        #endif

        // 1. Stop audio playback immediately
        audioPlayback.stop()

        // 2. Clear any pending response state
        isWaitingForResponse = false
        isSpeaking = false

        // 3. Reset echo gate counter for fresh start
        echoGateFramesAboveThreshold = 0

        // 4. Send response.cancel to stop server from generating more audio
        webSocketManager.send(["type": "response.cancel"])
        #if DEBUG
        Log.voice.debug("[Voice] Barge-in: sent response.cancel to server")
        #endif

        // 5. Clear the input audio buffer on server to start fresh
        webSocketManager.send(["type": "input_audio_buffer.clear"])

        // 6. Notify delegate of barge-in
        delegate?.voiceService(self, didEmit: .bargeInTriggered)

        // 7. Ensure microphone capture continues for user's new input
        if !isListening {
            do {
                try startListening()
                #if DEBUG
                Log.voice.debug("[Voice] Barge-in: restarted listening")
                #endif
            } catch {
                #if DEBUG
                Log.voice.error("[Voice] Barge-in: failed to restart listening: \(error)")
                #endif
            }
        }
    }

    /// Just stop listening without requesting response (for muting)
    func stopListening() {
        guard isListening else { return }

        audioCapture.stopCapture()
        isListening = false
        
        #if DEBUG
        Log.voice.debug("[Voice] Stopped listening (muted)")
        #endif
    }

    /// Change the AI voice (premium only for non-ara voices)
    func setVoice(_ voice: GrokVoice) async throws {
        guard isPremium || voice == .ara else {
            throw VoiceError.premiumRequired
        }

        currentVoice = voice

        if connectionState.isConnected {
            try await configureSession()
        }

        try await saveVoicePreference(voice)
    }

    // MARK: - Emotion Settings

    /// Enable or disable emotion analysis
    /// Consent is granted/revoked based on this setting for privacy compliance
    func setEmotionAnalysisEnabled(_ enabled: Bool) {
        emotionAnalysisEnabled = enabled

        // Persist the setting
        UserDefaults.standard.set(enabled, forKey: "voiceEmotionAnalysisEnabled")

        // Enable/disable audio buffer accumulation (critical for performance)
        audioCapture.emotionBufferEnabled = enabled

        // Grant or revoke consent based on user preference
        emotionAnalyzer.setVoiceConsent(enabled)

        if !enabled {
            // Clear all emotion state when disabled
            currentEmotion = nil
            emotionConfidence = 0
            emotionHistory = []  // Clear history to respect user's privacy choice
            lastEmotionAnalysisTime = nil
            audioCapture.clearRollingBuffer()
        }
        #if DEBUG
        Log.voice.debug("[Voice] Emotion analysis \(enabled ? "enabled" : "disabled"), consent \(enabled ? "granted" : "revoked")")
        #endif
    }

    /// Set emotion sensitivity threshold (0.4 - 0.8)
    func setEmotionSensitivity(_ threshold: Double) {
        emotionSensitivityThreshold = max(0.4, min(0.8, threshold))
        #if DEBUG
        Log.voice.debug("[Voice] Emotion sensitivity set to \(self.emotionSensitivityThreshold)")
        #endif
    }

    // MARK: - Private Methods - Connection

    private func requestMicrophonePermission() async throws {
        let audioApp = AVAudioApplication.shared
        switch audioApp.recordPermission {
        case .granted:
            return
        case .denied:
            throw VoiceError.microphonePermissionDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            if !granted {
                throw VoiceError.microphonePermissionDenied
            }
        @unknown default:
            throw VoiceError.microphonePermissionDenied
        }
    }

    private func fetchVoiceToken() async throws -> VoiceTokenResponse {
        let generation = connectionGeneration
        do {
            // Refresh session to ensure we have a valid token
            #if DEBUG
            Log.voice.debug("[VoiceToken] Refreshing session...")
            #endif

            // First try to get the current session
            let currentSession = try? await supabase.auth.session
            #if DEBUG
            if let current = currentSession {
                Log.voice.debug("[VoiceToken] Current session exists, user: \(current.user.id)")
                Log.voice.debug("[VoiceToken] Token expires at: \(current.expiresAt)")
            } else {
                Log.voice.debug("[VoiceToken] No current session found")
            }
            #endif

            // Always refresh to get a fresh token
            let session = try await supabase.auth.session
            #if DEBUG
            Log.voice.debug("[VoiceToken] Session refreshed successfully, user: \(session.user.id)")
            Log.voice.debug("[VoiceToken] New token expires at: \(session.expiresAt)")
            Log.voice.debug("[VoiceToken] Access token retrieved (redacted), length: \(session.accessToken.count)")
            #endif

            // Use the global supabase client which should now have the refreshed session
            #if DEBUG
            Log.voice.debug("[VoiceToken] Calling voice-token function...")
            #endif

            // Use typed response - SDK will decode automatically
            // SDK should include auth header automatically after session refresh
            // But we explicitly pass it to ensure the refreshed token is used
            let authHeader = "Bearer \(session.accessToken)"
            #if DEBUG
            Log.voice.debug("[VoiceToken] Auth header constructed successfully")
            #endif

            try Task.checkCancellation()
            guard connectionGeneration == generation else { throw CancellationError() }
            let tokenResponse: VoiceTokenResponse = try await supabase.functions.invoke(
                "test-auth-diagnostic",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": authHeader],
                    body: ["transport": "relay"]
                )
            )
            guard !Task.isCancelled, connectionGeneration == generation else {
                await Task { @MainActor in
                    await endSession(sessionId: tokenResponse.sessionId, durationSeconds: 0, messagesCount: 0)
                }.value
                throw CancellationError()
            }
            #if DEBUG
            Log.voice.debug("[VoiceToken] Got token for voice successfully (token redacted from logs)")
            #endif
            return tokenResponse
        } catch let error as FunctionsError {
            #if DEBUG
            Log.voice.debug("[VoiceToken] FunctionsError: \(error)")
            #endif
            switch error {
            case .httpError(let code, let data):
                #if DEBUG
                Log.voice.debug("[VoiceToken] HTTP error status: \(code)")
                // Always log raw data for debugging
                if let rawString = String(data: data, encoding: .utf8) {
                    Log.voice.debug("[VoiceToken] Raw error response: \(rawString)")
                } else {
                    Log.voice.debug("[VoiceToken] Raw error data (non-UTF8): \(data.count) bytes")
                }
                #endif

                // Try to decode the error response
                let errorResponse = try? JSONDecoder().decode(VoiceErrorResponse.self, from: data)
                #if DEBUG
                if let errorResponse = errorResponse {
                    Log.voice.debug("[VoiceToken] Decoded error - code: \(errorResponse.code), message: \(errorResponse.error)")
                } else {
                    Log.voice.debug("[VoiceToken] Failed to decode error response as VoiceErrorResponse")
                }
                #endif

                // Handle specific error codes
                if errorResponse?.code == "SESSION_LIMIT_REACHED" {
                    throw VoiceError.connectionFailed(sessionLimitMessage)
                }
                if errorResponse?.code == "QUOTA_EXCEEDED" || code == 403 {
                    // 403 Forbidden typically means quota exceeded for this endpoint
                    throw VoiceError.quotaExceeded
                }
                if errorResponse?.code == "UNAUTHORIZED" || code == 401 {
                    throw VoiceError.notAuthorized
                }
                if errorResponse?.code == "RATE_LIMITED" || code == 429 {
                    throw VoiceError.networkUnavailable
                }

                throw VoiceError.tokenGenerationFailed
            case .relayError:
                throw VoiceError.networkUnavailable
            }
        } catch let error as VoiceError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            #if DEBUG
            Log.voice.debug("[VoiceToken] Unknown error: \(error)")
            #endif
            throw VoiceError.tokenGenerationFailed
        }
    }

    private func configureSession() async throws {
        #if DEBUG
        Log.voice.debug("[Voice] Configuring session with voice: \(self.currentVoice.rawValue)")
        #endif

        // xAI Grok Voice API session configuration
        // Using server VAD for natural conversation flow
        // The server handles: speech detection → auto-commit → auto-respond
        // We just stream audio continuously and handle playback/barge-in
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["audio", "text"],
                "instructions": voiceInstructions,
                "voice": currentVoice.rawValue,
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": 24000],
                        "transcription": ["model": "grok-transcribe"],
                    ],
                    "output": ["format": ["type": "audio/pcm", "rate": 24000]],
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.15,
                    "prefix_padding_ms": 300,  // Reduced from 400 for faster start detection
                    "silence_duration_ms": 1200,  // Increased from 700 to allow natural breathing pauses during speech
                    "create_response": true,
                ],
            ],
        ]

        #if DEBUG
        if let jsonData = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            Log.voice.debug("[Voice] Session config: \(jsonStr)")
        }
        #endif

        webSocketManager.send(config)
    }

    // MARK: - Private Methods - Audio

    // Echo gate: tracks consecutive frames above threshold during AI playback
    // Requires sustained speech (not just a brief spike) to trigger barge-in
    // Higher threshold + more frames = stronger echo rejection
    private var echoGateFramesAboveThreshold: Int = 0
    private var echoGateFramesBelowThreshold: Int = 0  // Track consecutive low frames for grace period
    private let echoGateRequiredFrames: Int = 5  // ~210ms sustained speech required (increased from 3)
    private let echoGateGracePeriodFrames: Int = 2  // Allow 2 consecutive low frames (~84ms) before resetting
    private let echoGateThreshold: Float = 0.50  // Higher threshold to filter speaker echo (increased from 0.35)

    // Initial playback suppression: block all audio for first 300ms of AI speech
    // This prevents the initial burst of echo before the echo gate kicks in
    private var playbackStartTime: Date?
    private let playbackSuppressionDuration: TimeInterval = 0.3

    /// Determines if audio should be suppressed to prevent echo
    /// Encapsulates all echo suppression logic in one place for maintainability
    /// - Returns: true if audio should be suppressed (dropped), false if it should be sent
    private func shouldSuppressAudioForEcho() -> Bool {
        // 1. Initial playback suppression: block audio for first 300ms of AI speech
        // This prevents the initial burst of echo before the echo gate kicks in
        if isSpeaking, let startTime = playbackStartTime {
            let timeSinceStart = Date().timeIntervalSince(startTime)
            if timeSinceStart < playbackSuppressionDuration {
                return true  // Suppress during initial playback window
            }
        }

        // 2. Echo gate: when AI is speaking, require sustained high mic level
        // This prevents the AI's own audio from triggering false barge-ins
        // iOS AEC handles most echo, but this provides an additional safety layer
        if isSpeaking {
            if micLevel >= echoGateThreshold {
                echoGateFramesAboveThreshold += 1
                echoGateFramesBelowThreshold = 0  // Reset low frame counter when above threshold

                // Only allow audio after sustained speech is detected
                if echoGateFramesAboveThreshold < echoGateRequiredFrames {
                    #if DEBUG
                    if echoGateFramesAboveThreshold == 1 {
                        Log.voice.debug("[Voice] Echo gate: potential speech detected, waiting for sustained input (mic: \(self.micLevel))")
                    }
                    #endif
                    return true  // Suppress until sustained speech confirmed
                }

                #if DEBUG
                if echoGateFramesAboveThreshold == echoGateRequiredFrames {
                    Log.voice.debug("[Voice] Echo gate: sustained speech confirmed, allowing barge-in (mic: \(self.micLevel))")
                }
                #endif
            } else {
                // Track consecutive low frames with grace period to avoid audio gaps on brief pauses
                echoGateFramesBelowThreshold += 1

                // Only reset after grace period expires (allows brief pauses in natural speech)
                if echoGateFramesBelowThreshold > echoGateGracePeriodFrames {
                    if echoGateFramesAboveThreshold > 0 {
                        #if DEBUG
                        Log.voice.debug("[Voice] Echo gate: level dropped for \(self.echoGateFramesBelowThreshold) frames, resetting (mic: \(self.micLevel))")
                        #endif
                    }
                    echoGateFramesAboveThreshold = 0
                    echoGateFramesBelowThreshold = 0
                }
                return true  // Suppress when mic level too low during playback
            }
        } else {
            // Reset echo gate counters when not speaking
            echoGateFramesAboveThreshold = 0
            echoGateFramesBelowThreshold = 0
        }

        // 3. Post-playback cooldown: wait briefly after playback ends for residual echo
        if let lastEnd = audioPlayback.lastPlaybackEndTime {
            let timeSincePlaybackEnd = Date().timeIntervalSince(lastEnd)
            if timeSincePlaybackEnd < audioPlayback.echoCooldownSeconds {
                return true  // Suppress during cooldown period
            }
        }

        return false  // No suppression needed, audio can be sent
    }

    private func sendAudioData(_ audioData: Data) {
        // Check all echo suppression conditions
        if shouldSuppressAudioForEcho() {
            return
        }

        let base64 = audioData.base64EncodedString()
        webSocketManager.send([
            "type": "input_audio_buffer.append",
            "audio": base64,
        ])
    }

    /// Inject emotion context into the conversation so AI can respond appropriately
    /// TEMPORARILY DISABLED - emotion analysis disabled
    private func injectEmotionContext(_ emotion: String, confidence: Double) {
        // DISABLED: Emotion analysis disabled
        return
    }

    // MARK: - Private Methods - WebSocket

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else {
                #if DEBUG
                Log.voice.debug("[Voice] Failed to convert message to data")
                #endif
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                Log.voice.debug("[Voice] Failed to parse JSON: \(String(text.prefix(200)))")
                #endif
                return
            }

            guard let type = json["type"] as? String else {
                #if DEBUG
                Log.voice.debug("[Voice] No 'type' in message: \(String(text.prefix(200)))")
                #endif
                return
            }

            handleEvent(type: type, json: json)
        case .data(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                Log.voice.debug("[Voice] Failed to parse binary JSON")
                #endif
                return
            }

            guard let type = json["type"] as? String else {
                #if DEBUG
                Log.voice.debug("[Voice] No 'type' in binary message")
                #endif
                return
            }

            handleEvent(type: type, json: json)
        @unknown default:
            #if DEBUG
            Log.voice.debug("[Voice] Unknown message format")
            #endif
            break
        }
    }

    private func handleEvent(type: String, json: [String: Any]) {
        #if DEBUG
        // Log all events for debugging
        Log.voice.debug("[Voice] Received event: \(type)")
        #endif

        switch type {
        case "session.created", "conversation.created":
            didReceiveSessionCreated = true
            #if DEBUG
            Log.voice.debug("[Voice] Session/conversation created successfully")
            #endif
            // Cancel timeout task and resume continuation
            sessionCreatedTimeoutTask?.cancel()
            sessionCreatedTimeoutTask = nil
            if let continuation = sessionCreatedContinuation {
                sessionCreatedContinuation = nil
                continuation.resume()
            }

        case "session.updated":
            didReceiveSessionUpdated = true
            #if DEBUG
            Log.voice.debug("[Voice] Session updated")
            #endif
            // Cancel timeout task and resume continuation
            sessionUpdatedTimeoutTask?.cancel()
            sessionUpdatedTimeoutTask = nil
            if let continuation = sessionUpdatedContinuation {
                sessionUpdatedContinuation = nil
                continuation.resume()
            }

        case "ping":
            // Respond to ping with pong to keep connection alive
            webSocketManager.send(["type": "pong"])

        case "input_audio_buffer.speech_started":
            #if DEBUG
            Log.voice.debug("[Voice] VAD detected speech start")
            #endif

            // Reset idle timer on speech activity
            resetIdleTimer()

            // Check if this is a barge-in situation (user speaking while AI is responding)
            let isBargeIn = isSpeaking || isWaitingForResponse

            if isBargeIn {
                #if DEBUG
                Log.voice.debug("[Voice] Barge-in detected: user speaking during AI response")
                #endif

                // 1. Stop audio playback immediately
                audioPlayback.stop()

                // 2. Cancel the ongoing response from server
                webSocketManager.send(["type": "response.cancel"])
                #if DEBUG
                Log.voice.debug("[Voice] Barge-in: sent response.cancel")
                #endif

                // 3. Update state
                isSpeaking = false
                isWaitingForResponse = false
                playbackStartTime = nil  // Reset so next response gets fresh suppression window

                // 4. Reset echo gate for fresh start
                echoGateFramesAboveThreshold = 0
                echoGateFramesBelowThreshold = 0

                // 5. Notify delegate of barge-in
                delegate?.voiceService(self, didEmit: .bargeInTriggered)
            }

            isUserSpeaking = true

        case "input_audio_buffer.speech_stopped":
            #if DEBUG
            Log.voice.debug("[Voice] VAD detected speech stop - server will auto-commit and respond")
            #endif

            // Reset idle timer on speech activity
            resetIdleTimer()

            isUserSpeaking = false
            // With server_vad + create_response: true, the server will:
            // 1. Automatically commit the audio buffer
            // 2. Automatically create a response
            // We don't need to do anything here - just wait for the response

            // Trigger emotion analysis (async, non-blocking)
            analyzeEmotionIfNeeded()

        case "input_audio_buffer.committed":
            #if DEBUG
            // Log details for debugging multi-turn issues
            if let itemId = json["item_id"] as? String {
                Log.voice.debug("[Voice] Audio buffer committed, item_id: \(itemId)")
            } else {
                Log.voice.debug("[Voice] Audio buffer committed (no item_id in response)")
            }
            #endif

        case "conversation.item.created":
            #if DEBUG
            if let item = json["item"] as? [String: Any],
               let itemId = item["id"] as? String,
               let role = item["role"] as? String {
                Log.voice.debug("[Voice] Conversation item created: id=\(itemId), role=\(role)")
            } else {
                Log.voice.debug("[Voice] Conversation item created")
            }
            #endif

        case "conversation.item.input_audio_transcription.updated", "conversation.item.input_audio_transcription.completed":
            // User's speech has been transcribed
            if let transcript = json["transcript"] as? String {
                #if DEBUG
                Log.voice.debug("[Voice] User transcript received")
                #endif
                userTranscribedText = transcript
            }

        case "response.created":
            #if DEBUG
            Log.voice.debug("[Voice] Response started (turn \(self.messageCount + 1))")
            #endif
            isWaitingForResponse = true
            isSpeaking = true
            playbackStartTime = Date()  // Track when playback started for echo suppression

        case "response.output_item.added":
            #if DEBUG
            Log.voice.debug("[Voice] Output item added")
            #endif

        case "response.audio.delta", "response.output_audio.delta":
            if let delta = json["delta"] as? String,
               let audioData = Data(base64Encoded: delta) {
                #if DEBUG
                Log.voice.debug("[Voice] Received audio delta: \(audioData.count) bytes")
                #endif
                audioPlayback.queueAudioChunk(audioData)
            }

        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                #if DEBUG
                Log.voice.debug("[Voice] Transcript delta received")
                #endif
                transcribedText += delta
            }

        case "response.text.delta":
            if let delta = json["delta"] as? String {
                #if DEBUG
                Log.voice.debug("[Voice] Text delta: \(delta)")
                #endif
                transcribedText += delta
            }

        case "response.done":
            #if DEBUG
            Log.voice.debug("[Voice] Response complete (turn \(self.messageCount + 1))")
            #endif
            self.messageCount += 1
            // NOTE: Do NOT set isSpeaking = false here!
            // Audio buffers are still playing. isSpeaking is set to false
            // only when playback actually completes in audioPlayback.onPlaybackEnd callback
            isWaitingForResponse = false

            // Reset idle timer after response completes
            resetIdleTimer()

            // A previous session must not clear a new session's transcript.
            let generation = connectionGeneration
            Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return }
                guard let self, self.connectionGeneration == generation, !self.isWaitingForResponse else { return }
                self.transcribedText = ""
            }

        case "response.audio.done", "response.text.done":
            #if DEBUG
            Log.voice.debug("[Voice] Audio/text stream done")
            #endif

        case "error", "session.error":
            let error = json["error"] as? [String: Any] ?? json
            let code = error["code"] as? String
            let message = error["message"] as? String ?? "Voice session ended. Tap to start a new session."
            let reachedLimit = code == "SESSION_LIMIT_REACHED" || message.lowercased() == "session limit reached"
            finishSession(message: reachedLimit ? sessionLimitMessage : message)

        default:
            #if DEBUG
            // Log ALL unknown events to discover xAI's actual event names
            Log.voice.debug("[Voice] Unhandled event type: \(type)")
            if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                Log.voice.debug("[Voice] Event data received")
            }
            #endif
        }
    }

    // MARK: - Private Methods - Session Management

    private func startUsageTimer() {
        stopUsageTimer() // Clear any existing timer

        // Update every 5 seconds - quota display doesn't need 1s precision
        // Reduces main thread work by 80%
        usageTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMinutesRemaining()
            }
        }
    }

    private func stopUsageTimer() {
        usageTimer?.invalidate()
        usageTimer = nil
    }

    // MARK: - Idle Timer Management

    /// Start the idle disconnect timer (called after connection established)
    private func startIdleTimer() {
        stopIdleTimer()
        lastSpeechActivityTime = Date()

        // Check every 5 seconds if we've exceeded idle threshold
        idleDisconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleTimeout()
            }
        }

        #if DEBUG
        Log.voice.debug("[Voice] Idle timer started (threshold: \(self.idleDisconnectThreshold)s)")
        #endif
    }

    /// Stop the idle disconnect timer
    private func stopIdleTimer() {
        idleDisconnectTimer?.invalidate()
        idleDisconnectTimer = nil
    }

    /// Reset the idle timer when speech activity is detected
    private func resetIdleTimer() {
        lastSpeechActivityTime = Date()

        #if DEBUG
        Log.voice.debug("[Voice] Idle timer reset")
        #endif
    }

    /// Check if idle threshold has been exceeded
    private func checkIdleTimeout() {
        guard let lastActivity = lastSpeechActivityTime,
              !isIdleDisconnected,
              connectionState.isConnected else { return }

        let elapsed = Date().timeIntervalSince(lastActivity)
        if elapsed >= idleDisconnectThreshold {
            finishSession(message: "Voice session ended after inactivity. Tap to start a new session.")
        }
    }

    private func updateMinutesRemaining() {
        guard let startTime = sessionStartTime else { return }
        
        let elapsedSeconds = Date().timeIntervalSince(startTime)
        let elapsedMinutes = elapsedSeconds / 60.0
        minutesRemaining = max(0, initialMinutesRemaining - elapsedMinutes)
        
        // Stop session when quota is exhausted
        if minutesRemaining <= 0 {
            finishSession(message: "Monthly voice quota reached. Your three free minutes have been used. Premium includes unlimited monthly minutes, with sessions up to two minutes.")
        }
    }

    private func endSession(sessionId: String, durationSeconds: Int, messagesCount: Int) async {
        struct EndSessionRequest: Encodable {
            let sessionId: String
            let durationSeconds: Int
            let messagesCount: Int
            let wasQuotaLimited: Bool

            enum CodingKeys: String, CodingKey {
                case sessionId = "session_id"
                case durationSeconds = "duration_seconds"
                case messagesCount = "messages_count"
                case wasQuotaLimited = "was_quota_limited"
            }
        }

        do {
            // Refresh session to ensure we have a valid token (not stale)
            let session = try await supabase.auth.session
            _ = try await supabase.functions.invoke(
                "voice-session-end",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: EndSessionRequest(
                        sessionId: sessionId,
                        durationSeconds: durationSeconds,
                        messagesCount: messagesCount,
                        wasQuotaLimited: false
                    )
                )
            )
        } catch {
            #if DEBUG
            Log.voice.debug("Failed to end session: \(error)")
            #endif
        }
    }

    private func saveVoicePreference(_ voice: GrokVoice) async throws {
        guard let session = try? await supabase.auth.session else { return }

        try await supabase
            .from("voice_settings")
            .upsert([
                "user_id": session.user.id.uuidString,
                "preferred_voice": voice.rawValue,
                "updated_at": ISO8601DateFormatter().string(from: Date()),
            ])
            .execute()
    }

    // MARK: - Private Methods - Emotion Analysis

    /// Analyze emotion from recent audio buffer after speech ends
    /// Runs asynchronously without blocking voice flow
    /// TEMPORARILY DISABLED - causing voice latency issues
    private func analyzeEmotionIfNeeded() {
        // DISABLED: Emotion analysis causing voice latency/cutoff issues
        // TODO: Re-enable after fixing performance problems
        return

    }

    /// Resample audio buffer - static function to allow calling from detached task
    /// - Parameters:
    ///   - inputBuffer: Source audio samples
    ///   - fromRate: Source sample rate (e.g., 24000)
    ///   - toRate: Target sample rate (e.g., 16000)
    /// - Returns: Resampled audio buffer
    private nonisolated static func resampleAudio(_ inputBuffer: [Float], fromRate: Double, toRate: Double) -> [Float] {
        // Validate inputs to prevent division by zero or invalid calculations
        guard !inputBuffer.isEmpty, fromRate > 0, toRate > 0 else { return [] }

        let ratio = fromRate / toRate
        let outputLength = Int(Double(inputBuffer.count) / ratio)

        guard outputLength > 0 else { return [] }

        var outputBuffer = [Float](repeating: 0, count: outputLength)

        // Linear interpolation resampling
        for i in 0..<outputLength {
            let sourceIndex = Double(i) * ratio
            let lowerIndex = Int(sourceIndex)
            let upperIndex = min(lowerIndex + 1, inputBuffer.count - 1)
            let fraction = Float(sourceIndex - Double(lowerIndex))

            outputBuffer[i] = inputBuffer[lowerIndex] * (1 - fraction) + inputBuffer[upperIndex] * fraction
        }

        return outputBuffer
    }

    /// Handle successful emotion analysis result
    private func handleEmotionResult(_ result: EmotionResult) {
        currentEmotion = result
        emotionConfidence = result.confidence

        // Add to history with timestamp (fallback to Date() if session not started)
        let startTime = sessionStartTime ?? Date()
        let snapshot = EmotionSnapshot(
            from: result,
            sessionStartTime: startTime,
            transcript: nil
        )
        emotionHistory.append(snapshot)

        // Enforce max history size (FIFO - remove oldest entries)
        if emotionHistory.count > maxEmotionHistorySize {
            emotionHistory.removeFirst(emotionHistory.count - maxEmotionHistorySize)
        }

        // Inject emotion context into conversation for AI awareness
        // This will be visible to the AI for subsequent responses
        injectEmotionContext(result.emotion, confidence: result.confidence)

        // Emit event to delegate
        delegate?.voiceService(self, didEmit: .emotionDetected(result))

        #if DEBUG
        Log.voice.debug("[Voice] Emotion detected: \(result.emotion) @ \(result.confidence) (history: \(self.emotionHistory.count))")
        #endif
    }
}

// MARK: - Helper Types

private struct VoiceErrorResponse: Codable {
    let error: String
    let code: String
    let minutesRemaining: Double?
    let upgradeRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case error, code
        case minutesRemaining = "minutes_remaining"
        case upgradeRequired = "upgrade_required"
    }
}
