import Foundation
import AVFoundation
import Combine
import Supabase

/// Service for real-time voice conversations using Grok Voice Agent API
@MainActor
final class GrokVoiceService: ObservableObject {

    // MARK: - Connection State

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting
        case error(String)

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    // MARK: - Published Properties

    @Published private(set) var connectionState: ConnectionState = .disconnected
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false // AI is speaking
    @Published private(set) var isUserSpeaking = false // VAD detected user speech
    @Published private(set) var transcribedText = ""
    @Published private(set) var minutesRemaining: Double = 0
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

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Audio - separate engines for recording and playback to avoid conflicts
    private let recordingEngine = AVAudioEngine()
    private let playbackEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var playbackBuffer: [Data] = []
    private var isPlayingAudio = false
    private var audioTapBufferCount = 0

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

    // WebSocket send backpressure
    private var pendingSendCount = 0
    private let maxPendingSends = 10

    // Playback buffer limits
    private let maxPlaybackBufferSize = 50  // ~5 seconds at typical chunk rate

    // Audio level smoothing for orb visualization
    private var previousMicLevel: Float = 0
    private var previousPlaybackLevel: Float = 0
    private let levelAttackCoeff: Float = 0.3   // Fast response to increases
    private let levelReleaseCoeff: Float = 0.9  // Slow decay
    private let noiseFloorDb: Float = -50
    private let ceilingDb: Float = -6

    // Configuration
    private let sampleRate: Double = 24000
    private let channelCount: AVAudioChannelCount = 1

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
        setupAudioComponents()
    }

    private func setupAudioComponents() {
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: true
        )

        // Set up playback engine (separate from recording)
        audioPlayer = AVAudioPlayerNode()
        if let player = audioPlayer, let format = audioFormat {
            playbackEngine.attach(player)
            playbackEngine.connect(player, to: playbackEngine.mainMixerNode, format: format)
            player.volume = 1.0
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

            try await connectWebSocket(token: tokenResponse.token)

            // Wait for session.created event from the server
            #if DEBUG
            print("[Voice] Waiting for session.created event...")
            #endif
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sessionCreatedContinuation = continuation

                // Set timeout for session creation - store task to cancel if event arrives
                sessionCreatedTimeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    if !Task.isCancelled, let cont = self.sessionCreatedContinuation {
                        self.sessionCreatedContinuation = nil
                        cont.resume(throwing: VoiceError.connectionTimeout)
                    }
                }
            }

            // Now configure the session with our settings
            try await configureSession()

            // Wait for session.updated confirmation
            #if DEBUG
            print("[Voice] Waiting for session.updated...")
            #endif
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sessionUpdatedContinuation = continuation

                // Set timeout - store task to cancel if event arrives
                sessionUpdatedTimeoutTask = Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if !Task.isCancelled, let cont = self.sessionUpdatedContinuation {
                        self.sessionUpdatedContinuation = nil
                        cont.resume(throwing: VoiceError.connectionTimeout)
                    }
                }
            }

            connectionState = .connected
            sessionStartTime = Date()
            messageCount = 0
            #if DEBUG
            print("[Voice] Connection complete, ready for audio")
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
        stopPlayback()
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

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil

        // Invalidate URLSession to prevent memory leak
        urlSession?.invalidateAndCancel()
        urlSession = nil

        await endSession()

        connectionState = .disconnected
        transcribedText = ""
        sessionId = nil
        sessionStartTime = nil
        audioSendCount = 0
        isWaitingForResponse = false
        pendingSendCount = 0
    }

    /// Start listening for voice input
    func startListening() throws {
        #if DEBUG
        print("[Voice] startListening called, connectionState: \(connectionState)")
        #endif
        guard connectionState.isConnected else {
            #if DEBUG
            print("[Voice] Not connected, cannot start listening")
            #endif
            throw VoiceError.notConnected
        }

        guard !isListening else {
            #if DEBUG
            print("[Voice] Already listening, skipping")
            #endif
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()

            #if DEBUG
            // Check current permission status
            print("[Voice] Record permission: \(audioSession.recordPermission.rawValue)")
            print("[Voice] Current route: \(audioSession.currentRoute.inputs.map { $0.portName })")
            #endif

            // Use .videoRecording mode for natural audio levels (no AGC compression)
            // .voiceChat mode applies aggressive gain control that reduces volume
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try audioSession.setActive(true)
            #if DEBUG
            print("[Voice] Audio session configured for playAndRecord")
            print("[Voice] Audio session isOtherAudioPlaying: \(audioSession.isOtherAudioPlaying)")
            print("[Voice] Audio route after activation: \(audioSession.currentRoute.inputs.map { $0.portName })")
            #endif

            let inputNode = recordingEngine.inputNode

            // Force refresh the input node format
            let hardwareFormat = inputNode.inputFormat(forBus: 0)
            #if DEBUG
            print("[Voice] Hardware input format: sampleRate=\(hardwareFormat.sampleRate), channels=\(hardwareFormat.channelCount)")
            #endif

            let nativeFormat = inputNode.outputFormat(forBus: 0)
            #if DEBUG
            print("[Voice] Native output format: sampleRate=\(nativeFormat.sampleRate), channels=\(nativeFormat.channelCount), format=\(nativeFormat.commonFormat.rawValue)")
            #endif

            // Check if format is valid
            guard nativeFormat.sampleRate > 0 && nativeFormat.channelCount > 0 else {
                #if DEBUG
                print("[Voice] ERROR: Invalid audio format!")
                #endif
                throw VoiceError.audioSessionFailed("Invalid audio format - no input available")
            }

            // Create converter from native format to xAI's expected format (24kHz Int16)
            guard let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: true
            ) else {
                throw VoiceError.audioSessionFailed("Failed to create target audio format")
            }
            #if DEBUG
            print("[Voice] Target format: sampleRate=\(targetFormat.sampleRate), channels=\(targetFormat.channelCount)")
            #endif

            let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
            #if DEBUG
            if converter == nil {
                print("[Voice] WARNING: Failed to create audio converter!")
            } else {
                print("[Voice] Audio converter created successfully")
            }
            #endif

            // Remove any existing tap first
            inputNode.removeTap(onBus: 0)

            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: nativeFormat
            ) { [weak self] buffer, time in
                self?.audioTapBufferCount += 1
                #if DEBUG
                if self?.audioTapBufferCount == 1 || (self?.audioTapBufferCount ?? 0) % 50 == 0 {
                    print("[Voice] Audio tap buffer #\(self?.audioTapBufferCount ?? 0), frames: \(buffer.frameLength), time: \(time.sampleTime)")
                }
                #endif
                self?.processAndConvertAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }
            #if DEBUG
            print("[Voice] Audio tap installed on input node")
            #endif

            recordingEngine.prepare()
            try recordingEngine.start()
            #if DEBUG
            print("[Voice] Recording engine started, isRunning: \(recordingEngine.isRunning)")
            print("[Voice] Input node isVoiceProcessingEnabled: \(inputNode.isVoiceProcessingEnabled)")
            #endif

            isListening = true
            audioTapBufferCount = 0
            #if DEBUG
            print("[Voice] Now listening for audio input")
            #endif
        } catch {
            #if DEBUG
            print("[Voice] startListening error: \(error)")
            #endif
            throw VoiceError.audioSessionFailed(error.localizedDescription)
        }
    }

    /// Force commit audio buffer and get response (for edge cases when VAD doesn't trigger)
    /// With server_vad enabled, the server will auto-respond after commit
    func stopListeningAndRespond() {
        guard connectionState.isConnected else {
            #if DEBUG
            print("[Voice] Not connected, cannot send")
            #endif
            return
        }

        guard !isWaitingForResponse else {
            #if DEBUG
            print("[Voice] Already waiting for response, ignoring")
            #endif
            return
        }

        #if DEBUG
        print("[Voice] Force commit (turn \(messageCount + 1))...")
        #endif
        isWaitingForResponse = true
        transcribedText = ""

        // Just commit - with server_vad + create_response: true, server will auto-respond
        sendMessage(["type": "input_audio_buffer.commit"])

        // Note: We don't stop listening or send response.create
        // The server handles everything after commit
        // Audio capture continues for the next turn
    }

    /// Just stop listening without requesting response (for muting)
    func stopListening() {
        guard isListening else { return }

        recordingEngine.inputNode.removeTap(onBus: 0)
        recordingEngine.stop()

        isListening = false
        #if DEBUG
        print("[Voice] Stopped listening (muted)")
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
        let audioSession = AVAudioSession.sharedInstance()
        switch audioSession.recordPermission {
        case .granted:
            return
        case .denied:
            throw VoiceError.microphonePermissionDenied
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                audioSession.requestRecordPermission { granted in
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
            print("[VoiceToken] Refreshing session...")
            #endif
            _ = try await supabase.auth.refreshSession()

            // Use the global supabase client which should now have the refreshed session
            #if DEBUG
            print("[VoiceToken] Calling voice-token function...")
            #endif

            // Use typed response - SDK will decode automatically
            let tokenResponse: VoiceTokenResponse = try await supabase.functions.invoke(
                "voice-token",
                options: FunctionInvokeOptions()
            )
            #if DEBUG
            print("[VoiceToken] Got token for voice: \(tokenResponse.voice)")
            #endif
            return tokenResponse
        } catch let error as FunctionsError {
            #if DEBUG
            print("[VoiceToken] FunctionsError: \(error)")
            #endif
            switch error {
            case .httpError(let code, let data):
                #if DEBUG
                // Only log HTTP status code, not response body which may contain PII
                print("[VoiceToken] HTTP error status: \(code)")
                #endif
                if let errorResponse = try? JSONDecoder().decode(VoiceErrorResponse.self, from: data) {
                    #if DEBUG
                    // Log parsed error code (safe - known structure)
                    print("[VoiceToken] Error code: \(errorResponse.code)")
                    #endif
                    if errorResponse.code == "QUOTA_EXCEEDED" {
                        throw VoiceError.quotaExceeded
                    }
                    if errorResponse.code == "UNAUTHORIZED" {
                        throw VoiceError.notAuthorized
                    }
                }
                throw VoiceError.tokenGenerationFailed
            case .relayError:
                throw VoiceError.networkUnavailable
            }
        } catch let error as VoiceError {
            throw error
        } catch {
            #if DEBUG
            print("[VoiceToken] Unknown error: \(error)")
            #endif
            throw VoiceError.tokenGenerationFailed
        }
    }

    private func connectWebSocket(token: String) async throws {
        guard let url = URL(string: "wss://api.x.ai/v1/realtime") else {
            throw VoiceError.connectionFailed("Invalid WebSocket URL")
        }
        #if DEBUG
        print("[Voice] Connecting to WebSocket...")
        #endif

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300

        urlSession = URLSession(configuration: configuration)
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()
        #if DEBUG
        print("[Voice] WebSocket task resumed, starting message receiver...")
        #endif

        receiveMessages()
    }

    private func configureSession() async throws {
        #if DEBUG
        print("[Voice] Configuring session with voice: \(currentVoice.rawValue)")
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
            print("[Voice] Session config: \(jsonStr)")
        }
        #endif

        sendMessage(config)
    }

    // MARK: - Private Methods - WebSocket

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                #if DEBUG
                switch message {
                case .string(let text):
                    print("[Voice] WS received string message (\(text.count) chars)")
                case .data(let data):
                    print("[Voice] WS received data message (\(data.count) bytes)")
                @unknown default:
                    print("[Voice] WS received unknown message type")
                }
                #endif
                Task { @MainActor in
                    self.handleWebSocketMessage(message)
                }
                self.receiveMessages()
            case .failure(let error):
                #if DEBUG
                print("[Voice] WS receive error: \(error.localizedDescription)")
                #endif
                Task { @MainActor in
                    self.stopListening()
                    self.connectionState = .error("Connection lost")
                }
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8) else {
                #if DEBUG
                print("[Voice] Failed to convert message to data")
                #endif
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                print("[Voice] Failed to parse JSON: \(String(text.prefix(200)))")
                #endif
                return
            }

            guard let type = json["type"] as? String else {
                #if DEBUG
                print("[Voice] No 'type' in message: \(String(text.prefix(200)))")
                #endif
                return
            }

            handleEvent(type: type, json: json)
        case .data(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                #if DEBUG
                print("[Voice] Failed to parse binary JSON")
                #endif
                return
            }

            guard let type = json["type"] as? String else {
                #if DEBUG
                print("[Voice] No 'type' in binary message")
                #endif
                return
            }

            handleEvent(type: type, json: json)
        @unknown default:
            #if DEBUG
            print("[Voice] Unknown message format")
            #endif
            break
        }
    }

    private func handleEvent(type: String, json: [String: Any]) {
        #if DEBUG
        // Log all events for debugging
        print("[Voice] Received event: \(type)")
        #endif

        switch type {
        case "session.created", "conversation.created":
            #if DEBUG
            print("[Voice] Session/conversation created successfully")
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
            print("[Voice] Session updated")
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
            sendMessage(["type": "pong"])

        case "input_audio_buffer.speech_started":
            #if DEBUG
            print("[Voice] VAD detected speech start")
            #endif
            isUserSpeaking = true
            // User started speaking - implement barge-in
            if isSpeaking || isPlayingAudio {
                #if DEBUG
                print("[Voice] Barge-in: stopping AI playback")
                #endif
                stopPlayback()
            }
            isWaitingForResponse = false // Reset in case we were waiting

        case "input_audio_buffer.speech_stopped":
            #if DEBUG
            print("[Voice] VAD detected speech stop - server will auto-commit and respond")
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
                print("[Voice] Audio buffer committed, item_id: \(itemId)")
            } else {
                print("[Voice] Audio buffer committed (no item_id in response)")
            }
            #endif

        case "conversation.item.created":
            #if DEBUG
            if let item = json["item"] as? [String: Any],
               let itemId = item["id"] as? String,
               let role = item["role"] as? String {
                print("[Voice] Conversation item created: id=\(itemId), role=\(role)")
            } else {
                print("[Voice] Conversation item created")
            }
            #endif

        case "response.created":
            #if DEBUG
            print("[Voice] Response started (turn \(messageCount + 1))")
            #endif
            isWaitingForResponse = true
            isSpeaking = true

        case "response.output_item.added":
            #if DEBUG
            print("[Voice] Output item added")
            #endif

        case "response.audio.delta", "response.output_audio.delta":
            if let delta = json["delta"] as? String,
               let audioData = Data(base64Encoded: delta) {
                #if DEBUG
                print("[Voice] Received audio delta: \(audioData.count) bytes")
                #endif
                queueAudioPlayback(audioData)
            }

        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                #if DEBUG
                print("[Voice] Transcript delta: \(delta)")
                #endif
                transcribedText += delta
            }

        case "response.text.delta":
            if let delta = json["delta"] as? String {
                #if DEBUG
                print("[Voice] Text delta: \(delta)")
                #endif
                transcribedText += delta
            }

        case "response.done":
            #if DEBUG
            print("[Voice] Response complete (turn \(messageCount + 1))")
            #endif
            messageCount += 1
            isSpeaking = false
            isWaitingForResponse = false

            // With server_vad, we keep listening continuously
            // No need to restart - audio capture should already be running
            // The server will detect when user speaks next
            Task { @MainActor in
                // Wait for playback buffer to drain
                var waitCount = 0
                while !self.playbackBuffer.isEmpty || self.isPlayingAudio {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    waitCount += 1
                    if waitCount > 100 { // Max 10 seconds
                        #if DEBUG
                        print("[Voice] Playback wait timeout")
                        #endif
                        break
                    }
                }
                #if DEBUG
                print("[Voice] Playback finished after \(waitCount * 100)ms, ready for next turn")
                #endif

                // If we're not listening (e.g., due to audio session switch), restart
                if self.connectionState.isConnected && !self.isListening {
                    do {
                        try self.startListening()
                        #if DEBUG
                        print("[Voice] Restarted listening after playback")
                        #endif
                    } catch {
                        #if DEBUG
                        print("[Voice] Failed to restart listening: \(error)")
                        #endif
                    }
                }
            }

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
            print("[Voice] Audio/text stream done")
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
                print("[Voice] Error: \(code) - \(message)")
                #endif
                errorMessage = message
            } else {
                // Sometimes error is at root level
                let message = json["message"] as? String ?? "Unknown error"
                #if DEBUG
                print("[Voice] Error: \(message)")
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
            print("[Voice] Unhandled event type: \(type)")
            if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                print("[Voice] Event data: \(String(jsonStr.prefix(1000)))")
            }
            #endif
        }
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else {
            #if DEBUG
            print("[Voice] Failed to serialize message")
            #endif
            return
        }

        let messageType = message["type"] as? String ?? "unknown"

        // Apply backpressure for audio messages to prevent unbounded queue growth
        if messageType == "input_audio_buffer.append" {
            guard pendingSendCount < maxPendingSends else {
                // Drop message if queue is full - network can't keep up
                return
            }
        }

        // Log non-audio messages
        #if DEBUG
        if messageType != "input_audio_buffer.append" {
            print("[Voice] Sending: \(messageType)")
        }
        #endif

        pendingSendCount += 1
        webSocket?.send(.string(string)) { [weak self] error in
            self?.pendingSendCount -= 1
            if let error = error {
                #if DEBUG
                print("[Voice] WebSocket send error: \(error)")
                #endif
            }
        }
    }

    private func sendMessageWithConfirmation(_ message: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else {
            #if DEBUG
            print("[Voice] Failed to serialize message")
            #endif
            completion(false)
            return
        }

        #if DEBUG
        // Log non-audio messages
        if let type = message["type"] as? String, type != "input_audio_buffer.append" {
            print("[Voice] Sending: \(type)")
        }
        #endif

        webSocket?.send(.string(string)) { error in
            if let error = error {
                #if DEBUG
                print("[Voice] WebSocket send error: \(error)")
                #endif
                completion(false)
            } else {
                completion(true)
            }
        }
    }

    // MARK: - Private Methods - Audio Input

    private func processAndConvertAudioBuffer(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, targetFormat: AVAudioFormat) {
        guard let converter = converter else {
            // Fallback to direct processing if no converter
            processAudioBuffer(buffer)
            return
        }

        // Guard against division by zero
        guard buffer.format.sampleRate > 0 else {
            #if DEBUG
            print("[Voice] Invalid buffer sample rate: 0")
            #endif
            return
        }

        // Calculate output frame capacity based on sample rate ratio
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard outputFrameCapacity > 0, let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            #if DEBUG
            print("[Voice] Failed to create output buffer")
            #endif
            return
        }

        var error: NSError?
        var hasProvidedData = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if hasProvidedData {
                outStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedData = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            #if DEBUG
            print("[Voice] Conversion error: \(error)")
            #endif
            return
        }

        // Send converted buffer
        processAudioBuffer(outputBuffer)
    }

    private var audioSendCount = 0

    // Gain factor for microphone input (1.0 = no amplification)
    // Boost mic input for better VAD detection
    private let audioGain: Float = 3.0

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else {
            #if DEBUG
            print("[Voice] No int16 channel data in buffer")
            #endif
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            #if DEBUG
            print("[Voice] Buffer has 0 frames")
            #endif
            return
        }

        // Apply gain amplification to boost quiet microphone input
        let samples = channelData[0]
        var amplifiedData = Data(capacity: frameCount * 2)
        var sumSquares: Float = 0
        var maxSample: Int16 = 0

        for i in 0..<frameCount {
            let originalSample = samples[i]
            // Apply gain with clipping protection
            let amplified = Int32(Float(originalSample) * audioGain)
            let clippedSample = Int16(clamping: amplified)

            // Track stats on amplified audio
            sumSquares += Float(clippedSample) * Float(clippedSample)
            // Use Int32 for abs to avoid overflow when clippedSample is Int16.min (-32768)
            let absSample = Int16(clamping: abs(Int32(clippedSample)))
            if absSample > maxSample {
                maxSample = absSample
            }

            // Append to data (little-endian)
            var sample = clippedSample
            amplifiedData.append(Data(bytes: &sample, count: 2))
        }

        let base64 = amplifiedData.base64EncodedString()
        let rms = sqrt(sumSquares / Float(frameCount))
        let rmsDb = 20 * log10(max(rms, 1) / 32768.0)

        // Update mic level for orb visualization with smoothing
        let normalizedLevel = normalizeAudioLevel(rmsDb)
        updateMicLevel(normalizedLevel)

        audioSendCount += 1
        #if DEBUG
        if audioSendCount % 50 == 1 {
            print("[Voice] Sending audio chunk #\(audioSendCount), size: \(amplifiedData.count) bytes, RMS: \(String(format: "%.1f", rmsDb))dB, peak: \(maxSample), gain: \(audioGain)x")
        }
        #endif

        sendMessage([
            "type": "input_audio_buffer.append",
            "audio": base64,
        ])
    }

    /// Normalize dB level to 0.0-1.0 range
    private func normalizeAudioLevel(_ db: Float) -> Float {
        let normalized = (db - noiseFloorDb) / (ceilingDb - noiseFloorDb)
        return max(0, min(1, normalized))
    }

    /// Update mic level with attack/release smoothing
    private func updateMicLevel(_ newLevel: Float) {
        let coefficient = newLevel > previousMicLevel ? levelAttackCoeff : levelReleaseCoeff
        let smoothed = previousMicLevel * coefficient + newLevel * (1 - coefficient)
        previousMicLevel = smoothed
        Task { @MainActor in
            self.micLevel = smoothed
        }
    }

    /// Update playback level with attack/release smoothing
    private func updatePlaybackLevel(_ newLevel: Float) {
        let coefficient = newLevel > previousPlaybackLevel ? levelAttackCoeff : levelReleaseCoeff
        let smoothed = previousPlaybackLevel * coefficient + newLevel * (1 - coefficient)
        previousPlaybackLevel = smoothed
        Task { @MainActor in
            self.playbackLevel = smoothed
        }
    }

    /// Compute normalized RMS level from Int16 PCM data
    private func computePlaybackLevel(from data: Data) -> Float {
        let sampleCount = data.count / 2  // Int16 = 2 bytes
        guard sampleCount > 0 else { return 0 }

        var sumSquares: Float = 0
        let scale: Float = 1.0 / 32768.0

        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Float(samples[i]) * scale
                sumSquares += sample * sample
            }
        }

        let rms = sqrt(sumSquares / Float(sampleCount))
        guard rms > 0 else { return 0 }

        let db = 20 * log10(rms)
        return normalizeAudioLevel(db)
    }

    // MARK: - Private Methods - Audio Output

    private let minBuffersBeforePlay = 3  // Wait for 3 chunks before starting playback

    private func queueAudioPlayback(_ data: Data) {
        // Prevent unbounded memory growth - drop oldest chunk if buffer full
        if playbackBuffer.count >= maxPlaybackBufferSize {
            playbackBuffer.removeFirst()
            #if DEBUG
            print("[Voice] Warning: Playback buffer overflow, dropping oldest chunk")
            #endif
        }

        // Compute playback level for orb visualization
        let level = computePlaybackLevel(from: data)
        updatePlaybackLevel(level)

        playbackBuffer.append(data)

        if !isPlayingAudio {
            // Wait for minimum buffers before starting to prevent stuttering
            if playbackBuffer.count >= minBuffersBeforePlay {
                #if DEBUG
                print("[Voice] Starting playback with \(playbackBuffer.count) buffered chunks")
                #endif
                playNextAudioChunk()
            }
        } else {
            // Already playing - schedule this chunk immediately
            scheduleBufferForPlayback()
        }
    }

    private func scheduleBufferForPlayback() {
        guard !playbackBuffer.isEmpty,
              let player = audioPlayer,
              let format = audioFormat else {
            return
        }

        let audioData = playbackBuffer.removeFirst()
        let frameCount = AVAudioFrameCount(audioData.count / 2)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.int16ChannelData else {
            return
        }

        buffer.frameLength = frameCount
        audioData.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(channelData[0], baseAddress, audioData.count)
            }
        }

        // Schedule with completion handler for the late chunk
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.onPlaybackChunkComplete()
            }
        }
        #if DEBUG
        print("[Voice] Scheduled late chunk: \(audioData.count) bytes")
        #endif
    }

    private var isPlayerPlaying = false

    private func playNextAudioChunk() {
        guard let player = audioPlayer,
              let format = audioFormat else {
            isPlayingAudio = false
            isSpeaking = false
            isPlayerPlaying = false
            return
        }

        guard !playbackBuffer.isEmpty else {
            // No more buffers - wait for playback to finish
            return
        }

        isPlayingAudio = true
        isSpeaking = true

        // Start player FIRST before scheduling buffers
        if !isPlayerPlaying {
            #if DEBUG
            print("[Voice] Starting playback - playback engine running: \(playbackEngine.isRunning)")
            #endif

            // Ensure playback engine is running
            if !playbackEngine.isRunning {
                do {
                    // Note: Audio session already configured for recording
                    // Just start the playback engine
                    playbackEngine.prepare()
                    try playbackEngine.start()
                    #if DEBUG
                    print("[Voice] Playback engine started")
                    #endif
                } catch {
                    #if DEBUG
                    print("[Voice] Playback engine start error: \(error)")
                    #endif
                    return
                }
            }

            // Start player before scheduling
            player.play()
            isPlayerPlaying = true
        }

        // Schedule ALL available buffers at once for smooth playback
        var scheduledCount = 0
        while !playbackBuffer.isEmpty {
            let audioData = playbackBuffer.removeFirst()
            let frameCount = AVAudioFrameCount(audioData.count / 2)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                  let channelData = buffer.int16ChannelData else {
                continue
            }

            buffer.frameLength = frameCount
            audioData.withUnsafeBytes { rawBuffer in
                if let baseAddress = rawBuffer.baseAddress {
                    memcpy(channelData[0], baseAddress, audioData.count)
                }
            }

            // Last buffer gets completion handler to detect end of playback
            if playbackBuffer.isEmpty {
                player.scheduleBuffer(buffer) { [weak self] in
                    Task { @MainActor in
                        self?.onPlaybackChunkComplete()
                    }
                }
            } else {
                player.scheduleBuffer(buffer)
            }
            scheduledCount += 1
        }

        #if DEBUG
        print("[Voice] Scheduled \(scheduledCount) audio buffers")
        #endif
    }

    private func onPlaybackChunkComplete() {
        // Check if more buffers arrived while playing
        if !playbackBuffer.isEmpty {
            playNextAudioChunk()
        } else {
            // All done
            #if DEBUG
            print("[Voice] Playback complete")
            #endif
            isPlayingAudio = false
            isSpeaking = false
            isPlayerPlaying = false
        }
    }

    private func stopPlayback() {
        audioPlayer?.stop()

        // Stop playback engine to release audio resources
        if playbackEngine.isRunning {
            playbackEngine.stop()
        }

        playbackBuffer.removeAll()
        isPlayingAudio = false
        isSpeaking = false
        isPlayerPlaying = false
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
            print("Failed to end session: \(error)")
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
