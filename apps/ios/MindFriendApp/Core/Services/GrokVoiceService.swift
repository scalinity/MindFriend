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

    // MARK: - Delegate

    weak var delegate: VoiceServiceDelegate?

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    
    // Specialized components
    private let webSocketManager = VoiceWebSocketManager()
    private let audioCapture = VoiceAudioCapture()
    private let audioPlayback = VoiceAudioPlayback()

    // Session tracking
    private var sessionId: String?
    private var sessionStartTime: Date?
    private var initialMinutesRemaining: Double = 0
    private var messageCount = 0
    private var sessionCreatedContinuation: CheckedContinuation<Void, Error>?
    private var sessionUpdatedContinuation: CheckedContinuation<Void, Error>?
    private var sessionCreatedTimeoutTask: Task<Void, Never>?
    private var sessionUpdatedTimeoutTask: Task<Void, Never>?
    private var isWaitingForResponse = false
    private var usageTimer: Timer?

    // Voice instructions for MindFriend personality
    private let voiceInstructions = """
    You are a warm, supportive AI companion for MindFriend, a mental wellness app.

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
    }
    
    private func setupComponentCallbacks() {
        // WebSocket callbacks
        webSocketManager.onMessage = { [weak self] message in
            Task { @MainActor in
                self?.handleWebSocketMessage(message)
            }
        }
        
        webSocketManager.onConnectionLost = { [weak self] in
            Task { @MainActor in
                self?.stopListening()
                self?.connectionState = .reconnecting
            }
        }
        
        // Audio capture callbacks
        audioCapture.onAudioData = { [weak self] audioData in
            Task { @MainActor in
                self?.sendAudioData(audioData)
            }
        }
        
        audioCapture.onMicLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.micLevel = level
            }
        }
        
        // Audio playback callbacks
        audioPlayback.onPlaybackStart = { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = true
            }
        }
        
        audioPlayback.onPlaybackEnd = { [weak self] in
            Task { @MainActor in
                self?.isSpeaking = false
            }
        }
        
        audioPlayback.onPlaybackLevelUpdate = { [weak self] level in
            Task { @MainActor in
                self?.playbackLevel = level
            }
        }
    }

    // MARK: - Public Methods

    /// Connect to voice service
    func connect() async throws {
        guard connectionState != .connected && connectionState != .connecting else {
            return
        }

        connectionState = .connecting

        do {
            try await requestMicrophonePermission()

            let tokenResponse = try await fetchVoiceToken()

            minutesRemaining = tokenResponse.minutesRemaining
            initialMinutesRemaining = tokenResponse.minutesRemaining
            isPremium = tokenResponse.isPremium
            availableVoices = tokenResponse.grokAvailableVoices
            currentVoice = tokenResponse.grokVoice
            sessionId = tokenResponse.sessionId

            try await webSocketManager.connect(token: tokenResponse.token)

            // Wait for session.created event from the server
            #if DEBUG
            Log.voice.debug("[Voice] Waiting for session.created event...")
            #endif
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sessionCreatedContinuation = continuation

                // Set timeout for session creation - store task to cancel if event arrives
                sessionCreatedTimeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    guard let self, !Task.isCancelled else { return }
                    if let cont = self.sessionCreatedContinuation {
                        self.sessionCreatedContinuation = nil
                        cont.resume(throwing: VoiceError.connectionTimeout)
                    }
                }
            }

            // Now configure the session with our settings
            try await configureSession()

            // Wait for session.updated confirmation
            #if DEBUG
            Log.voice.debug("[Voice] Waiting for session.updated...")
            #endif
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

            connectionState = .connected
            sessionStartTime = Date()
            messageCount = 0
            #if DEBUG
            Log.voice.debug("[Voice] Connection complete, ready for audio")
            #endif

            // Start live usage timer for non-premium users
            if !isPremium {
                startUsageTimer()
            }

            // Auto-start listening for continuous conversation mode
            try startListening()
        } catch {
            connectionState = .error(error.localizedDescription)
            throw error
        }
    }

    /// Disconnect from voice service
    func disconnect() async {
        stopListening()
        audioPlayback.stop()
        stopUsageTimer()

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

        await endSession()

        connectionState = .disconnected
        transcribedText = ""
        sessionId = nil
        sessionStartTime = nil
        isWaitingForResponse = false
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
                Log.voice.debug("[VoiceToken] Token expires at: \(current.expiresAt ?? 0)")
            } else {
                Log.voice.debug("[VoiceToken] No current session found")
            }
            #endif

            // Always refresh to get a fresh token
            let session = try await supabase.auth.refreshSession()
            #if DEBUG
            Log.voice.debug("[VoiceToken] Session refreshed successfully, user: \(session.user.id)")
            Log.voice.debug("[VoiceToken] New token expires at: \(session.expiresAt ?? 0)")
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

            let tokenResponse: VoiceTokenResponse = try await supabase.functions.invoke(
                "voice-token",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": authHeader]
                )
            )
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
                #endif

                // Try to decode the error response
                let errorResponse = try? JSONDecoder().decode(VoiceErrorResponse.self, from: data)
                #if DEBUG
                if let errorResponse = errorResponse {
                    Log.voice.debug("[VoiceToken] Error code: \(errorResponse.code), message: \(errorResponse.error)")
                }
                #endif

                // Handle specific error codes
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
                "input_audio_format": "pcm16",
                "output_audio_format": "pcm16",
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.15,
                    "prefix_padding_ms": 400,
                    "silence_duration_ms": 1200,
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
    private var echoGateFramesAboveThreshold: Int = 0
    private let echoGateRequiredFrames: Int = 3  // ~125ms at 24kHz with 4096 buffer
    private let echoGateThreshold: Float = 0.20  // Mic level threshold during AI speech

    private func sendAudioData(_ audioData: Data) {
        // Echo gate: when AI is speaking, require sustained high mic level
        // This prevents the AI's own audio from triggering false barge-ins
        // iOS AEC handles most echo, but this provides an additional safety layer
        if isSpeaking {
            if micLevel >= echoGateThreshold {
                echoGateFramesAboveThreshold += 1

                // Only send audio after sustained speech is detected
                if echoGateFramesAboveThreshold < echoGateRequiredFrames {
                    #if DEBUG
                    if echoGateFramesAboveThreshold == 1 {
                        Log.voice.debug("[Voice] Echo gate: potential speech detected, waiting for sustained input (mic: \(self.micLevel))")
                    }
                    #endif
                    return
                }

                #if DEBUG
                if echoGateFramesAboveThreshold == echoGateRequiredFrames {
                    Log.voice.debug("[Voice] Echo gate: sustained speech confirmed, allowing barge-in (mic: \(self.micLevel))")
                }
                #endif
            } else {
                // Reset counter when level drops below threshold
                if echoGateFramesAboveThreshold > 0 {
                    #if DEBUG
                    Log.voice.debug("[Voice] Echo gate: level dropped, resetting (mic: \(self.micLevel))")
                    #endif
                }
                echoGateFramesAboveThreshold = 0
                return
            }
        } else {
            // Reset echo gate counter when not speaking
            echoGateFramesAboveThreshold = 0
        }

        // Echo suppression: wait briefly after playback ends to avoid residual echo
        if let lastEnd = audioPlayback.lastPlaybackEndTime {
            let timeSincePlaybackEnd = Date().timeIntervalSince(lastEnd)
            if timeSincePlaybackEnd < audioPlayback.echoCooldownSeconds {
                return
            }
        }

        let base64 = audioData.base64EncodedString()
        webSocketManager.send([
            "type": "input_audio_buffer.append",
            "audio": base64,
        ])
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

                // 4. Reset echo gate for fresh start
                echoGateFramesAboveThreshold = 0

                // 5. Notify delegate of barge-in
                delegate?.voiceService(self, didEmit: .bargeInTriggered)
            }

            isUserSpeaking = true

        case "input_audio_buffer.speech_stopped":
            #if DEBUG
            Log.voice.debug("[Voice] VAD detected speech stop - server will auto-commit and respond")
            #endif
            isUserSpeaking = false
            // With server_vad + create_response: true, the server will:
            // 1. Automatically commit the audio buffer
            // 2. Automatically create a response
            // We don't need to do anything here - just wait for the response

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

        case "response.created":
            #if DEBUG
            Log.voice.debug("[Voice] Response started (turn \(self.messageCount + 1))")
            #endif
            isWaitingForResponse = true
            isSpeaking = true

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
                Log.voice.debug("[Voice] Transcript delta: \(delta)")
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

            // Clear transcript after a delay
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                await MainActor.run {
                    if !self.isWaitingForResponse { // Only clear if not waiting for next response
                        self.transcribedText = ""
                    }
                }
            }

        case "response.audio.done", "response.text.done":
            #if DEBUG
            Log.voice.debug("[Voice] Audio/text stream done")
            #endif

        case "error":
            isWaitingForResponse = false
            isSpeaking = false
            transcribedText = ""  // Clear partial transcript on error
            let errorMessage: String
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown error"
                let code = error["code"] as? String ?? "unknown"
                #if DEBUG
                Log.voice.debug("[Voice] Error: \(code) - \(message)")
                #endif
                errorMessage = message
            } else {
                // Sometimes error is at root level
                let message = json["message"] as? String ?? "Unknown error"
                #if DEBUG
                Log.voice.debug("[Voice] Error: \(message)")
                #endif
                errorMessage = message
            }
            connectionState = .error(errorMessage)
            // Disconnect WebSocket on server error
            Task {
                await self.disconnect()
            }

        default:
            #if DEBUG
            // Log ALL unknown events to discover xAI's actual event names
            Log.voice.debug("[Voice] Unhandled event type: \(type)")
            if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                Log.voice.debug("[Voice] Event data: \(String(jsonStr.prefix(1000)))")
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

    private func updateMinutesRemaining() {
        guard let startTime = sessionStartTime else { return }
        
        let elapsedSeconds = Date().timeIntervalSince(startTime)
        let elapsedMinutes = elapsedSeconds / 60.0
        minutesRemaining = max(0, initialMinutesRemaining - elapsedMinutes)
        
        // Stop session when quota is exhausted
        if minutesRemaining <= 0 {
            stopUsageTimer()
            Task {
                await disconnect()
                connectionState = .error("Voice quota exceeded")
            }
        }
    }

    private func endSession() async {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else {
            return
        }

        let durationSeconds = Int(Date().timeIntervalSince(startTime))

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
            guard let session = try? await supabase.auth.session else { return }
            _ = try await supabase.functions.invoke(
                "voice-session-end",
                options: FunctionInvokeOptions(
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: EndSessionRequest(
                        sessionId: sessionId,
                        durationSeconds: durationSeconds,
                        messagesCount: messageCount,
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
