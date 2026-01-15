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
    @Published private(set) var isPremium = false

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?

    // Audio
    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var playbackBuffer: [Data] = []
    private var isPlayingAudio = false

    // Session tracking
    private var sessionId: String?
    private var sessionStartTime: Date?
    private var initialMinutesRemaining: Double = 0
    private var messageCount = 0
    private var sessionCreatedContinuation: CheckedContinuation<Void, Error>?
    private var sessionUpdatedContinuation: CheckedContinuation<Void, Error>?
    private var isWaitingForResponse = false
    private var usageTimer: Timer?

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

        audioPlayer = AVAudioPlayerNode()
        if let player = audioPlayer, let format = audioFormat {
            audioEngine.attach(player)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
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
            print("[Voice] Waiting for session.created event...")
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sessionCreatedContinuation = continuation

                // Set timeout for session creation
                Task {
                    try await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                    if let cont = self.sessionCreatedContinuation {
                        self.sessionCreatedContinuation = nil
                        cont.resume(throwing: VoiceError.connectionTimeout)
                    }
                }
            }

            // Now configure the session with our settings
            try await configureSession()

            // Wait for session.updated confirmation
            print("[Voice] Waiting for session.updated...")
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                sessionUpdatedContinuation = continuation

                Task {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    if let cont = self.sessionUpdatedContinuation {
                        self.sessionUpdatedContinuation = nil
                        cont.resume(throwing: VoiceError.connectionTimeout)
                    }
                }
            }

            connectionState = .connected
            sessionStartTime = Date()
            messageCount = 0
            print("[Voice] Connection complete, ready for audio")

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

        await endSession()

        connectionState = .disconnected
        transcribedText = ""
        sessionId = nil
        sessionStartTime = nil
        audioSendCount = 0
        isWaitingForResponse = false
    }

    /// Start listening for voice input
    func startListening() throws {
        print("[Voice] startListening called, connectionState: \(connectionState)")
        guard connectionState.isConnected else {
            print("[Voice] Not connected, cannot start listening")
            throw VoiceError.notConnected
        }

        guard !isListening else {
            print("[Voice] Already listening, skipping")
            return
        }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try audioSession.setActive(true)
            print("[Voice] Audio session configured for playAndRecord")

            let inputNode = audioEngine.inputNode
            // Use the input node's native format to avoid format mismatch
            let nativeFormat = inputNode.outputFormat(forBus: 0)
            print("[Voice] Native input format: sampleRate=\(nativeFormat.sampleRate), channels=\(nativeFormat.channelCount), format=\(nativeFormat.commonFormat.rawValue)")

            // Create converter from native format to xAI's expected format (24kHz Int16)
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: true
            )!
            print("[Voice] Target format: sampleRate=\(targetFormat.sampleRate), channels=\(targetFormat.channelCount)")

            let converter = AVAudioConverter(from: nativeFormat, to: targetFormat)
            if converter == nil {
                print("[Voice] WARNING: Failed to create audio converter!")
            } else {
                print("[Voice] Audio converter created successfully")
            }

            var tapBufferCount = 0
            inputNode.installTap(
                onBus: 0,
                bufferSize: 4096,
                format: nativeFormat
            ) { [weak self] buffer, _ in
                tapBufferCount += 1
                if tapBufferCount == 1 || tapBufferCount % 100 == 0 {
                    print("[Voice] Audio tap received buffer #\(tapBufferCount), frames: \(buffer.frameLength)")
                }
                self?.processAndConvertAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }
            print("[Voice] Audio tap installed on input node")

            audioEngine.prepare()
            try audioEngine.start()
            print("[Voice] Audio engine started, isRunning: \(audioEngine.isRunning)")

            isListening = true
            print("[Voice] Now listening for audio input")
        } catch {
            throw VoiceError.audioSessionFailed(error.localizedDescription)
        }
    }

    /// Force commit audio buffer and get response (for edge cases when VAD doesn't trigger)
    /// With server_vad enabled, the server will auto-respond after commit
    func stopListeningAndRespond() {
        guard connectionState.isConnected else {
            print("[Voice] Not connected, cannot send")
            return
        }

        guard !isWaitingForResponse else {
            print("[Voice] Already waiting for response, ignoring")
            return
        }

        print("[Voice] Force commit (turn \(messageCount + 1))...")
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

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        isListening = false
        print("[Voice] Stopped listening (muted)")
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
            print("[VoiceToken] Refreshing session...")
            _ = try await supabase.auth.refreshSession()

            // Use the global supabase client which should now have the refreshed session
            print("[VoiceToken] Calling voice-token function...")

            // Use typed response - SDK will decode automatically
            let tokenResponse: VoiceTokenResponse = try await supabase.functions.invoke(
                "voice-token",
                options: FunctionInvokeOptions()
            )
            print("[VoiceToken] Got token for voice: \(tokenResponse.voice)")
            return tokenResponse
        } catch let error as FunctionsError {
            print("[VoiceToken] FunctionsError: \(error)")
            switch error {
            case .httpError(let code, let data):
                print("[VoiceToken] HTTP error \(code): \(String(data: data, encoding: .utf8) ?? "nil")")
                if let errorResponse = try? JSONDecoder().decode(VoiceErrorResponse.self, from: data) {
                    print("[VoiceToken] Error code: \(errorResponse.code)")
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
            print("[VoiceToken] Unknown error: \(error)")
            throw VoiceError.tokenGenerationFailed
        }
    }

    private func connectWebSocket(token: String) async throws {
        let url = URL(string: "wss://api.x.ai/v1/realtime")!
        print("[Voice] Connecting to WebSocket: \(url)")

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300

        urlSession = URLSession(configuration: configuration)
        webSocket = urlSession?.webSocketTask(with: request)
        webSocket?.resume()
        print("[Voice] WebSocket task resumed, starting message receiver...")

        receiveMessages()
    }

    private func configureSession() async throws {
        print("[Voice] Configuring session with voice: \(currentVoice.rawValue)")

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
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24000
                        ]
                    ],
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24000
                        ]
                    ]
                ],
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.3,
                    "prefix_padding_ms": 300,
                    "silence_duration_ms": 800,
                    "create_response": true,
                ],
            ],
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            print("[Voice] Session config: \(jsonStr)")
        }

        sendMessage(config)
    }

    // MARK: - Private Methods - WebSocket

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("[Voice] WS received string message (\(text.count) chars)")
                case .data(let data):
                    print("[Voice] WS received data message (\(data.count) bytes)")
                @unknown default:
                    print("[Voice] WS received unknown message type")
                }
                Task { @MainActor in
                    self.handleWebSocketMessage(message)
                }
                self.receiveMessages()
            case .failure(let error):
                print("[Voice] WS receive error: \(error.localizedDescription)")
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
                print("[Voice] Failed to convert message to data")
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[Voice] Failed to parse JSON: \(String(text.prefix(200)))")
                return
            }

            guard let type = json["type"] as? String else {
                print("[Voice] No 'type' in message: \(String(text.prefix(200)))")
                return
            }

            handleEvent(type: type, json: json)
        case .data(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("[Voice] Failed to parse binary JSON")
                return
            }

            guard let type = json["type"] as? String else {
                print("[Voice] No 'type' in binary message")
                return
            }

            handleEvent(type: type, json: json)
        @unknown default:
            print("[Voice] Unknown message format")
            break
        }
    }

    private func handleEvent(type: String, json: [String: Any]) {
        // Log all events for debugging
        print("[Voice] Received event: \(type)")

        switch type {
        case "session.created", "conversation.created":
            print("[Voice] Session/conversation created successfully")
            // Resume the continuation to allow connect() to proceed
            if let continuation = sessionCreatedContinuation {
                sessionCreatedContinuation = nil
                continuation.resume()
            }

        case "session.updated":
            print("[Voice] Session updated")
            // Resume the continuation to allow connect() to proceed
            if let continuation = sessionUpdatedContinuation {
                sessionUpdatedContinuation = nil
                continuation.resume()
            }

        case "ping":
            // Respond to ping with pong to keep connection alive
            sendMessage(["type": "pong"])

        case "input_audio_buffer.speech_started":
            print("[Voice] VAD detected speech start")
            isUserSpeaking = true
            // User started speaking - implement barge-in
            if isSpeaking || isPlayingAudio {
                print("[Voice] Barge-in: stopping AI playback")
                stopPlayback()
            }
            isWaitingForResponse = false // Reset in case we were waiting

        case "input_audio_buffer.speech_stopped":
            print("[Voice] VAD detected speech stop - server will auto-commit and respond")
            isUserSpeaking = false
            // With server_vad + create_response: true, the server will:
            // 1. Automatically commit the audio buffer
            // 2. Automatically create a response
            // We don't need to do anything here - just wait for the response

        case "input_audio_buffer.committed":
            // Log details for debugging multi-turn issues
            if let itemId = json["item_id"] as? String {
                print("[Voice] Audio buffer committed, item_id: \(itemId)")
            } else {
                print("[Voice] Audio buffer committed (no item_id in response)")
            }

        case "conversation.item.created":
            if let item = json["item"] as? [String: Any],
               let itemId = item["id"] as? String,
               let role = item["role"] as? String {
                print("[Voice] Conversation item created: id=\(itemId), role=\(role)")
            } else {
                print("[Voice] Conversation item created")
            }

        case "response.created":
            print("[Voice] Response started (turn \(messageCount + 1))")
            isWaitingForResponse = true
            isSpeaking = true

        case "response.output_item.added":
            print("[Voice] Output item added")

        case "response.audio.delta", "response.output_audio.delta":
            if let delta = json["delta"] as? String,
               let audioData = Data(base64Encoded: delta) {
                print("[Voice] Received audio delta: \(audioData.count) bytes")
                queueAudioPlayback(audioData)
            }

        case "response.audio_transcript.delta", "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                print("[Voice] Transcript delta: \(delta)")
                transcribedText += delta
            }

        case "response.text.delta":
            if let delta = json["delta"] as? String {
                print("[Voice] Text delta: \(delta)")
                transcribedText += delta
            }

        case "response.done":
            print("[Voice] Response complete (turn \(messageCount + 1))")
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
                        print("[Voice] Playback wait timeout")
                        break
                    }
                }
                print("[Voice] Playback finished after \(waitCount * 100)ms, ready for next turn")

                // If we're not listening (e.g., due to audio session switch), restart
                if self.connectionState.isConnected && !self.isListening {
                    do {
                        try self.startListening()
                        print("[Voice] Restarted listening after playback")
                    } catch {
                        print("[Voice] Failed to restart listening: \(error)")
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
            print("[Voice] Audio/text stream done")

        case "error":
            isWaitingForResponse = false
            isSpeaking = false
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown error"
                let code = error["code"] as? String ?? "unknown"
                print("[Voice] Error: \(code) - \(message)")
                connectionState = .error(message)
            } else {
                // Sometimes error is at root level
                let message = json["message"] as? String ?? "Unknown error"
                print("[Voice] Error: \(message)")
                connectionState = .error(message)
            }

        default:
            // Log ALL unknown events to discover xAI's actual event names
            print("[Voice] Unhandled event type: \(type)")
            if let jsonData = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                print("[Voice] Event data: \(String(jsonStr.prefix(1000)))")
            }
        }
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else {
            print("[Voice] Failed to serialize message")
            return
        }

        // Log non-audio messages
        if let type = message["type"] as? String, type != "input_audio_buffer.append" {
            print("[Voice] Sending: \(type)")
        }

        webSocket?.send(.string(string)) { error in
            if let error = error {
                print("[Voice] WebSocket send error: \(error)")
            }
        }
    }

    private func sendMessageWithConfirmation(_ message: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else {
            print("[Voice] Failed to serialize message")
            completion(false)
            return
        }

        // Log non-audio messages
        if let type = message["type"] as? String, type != "input_audio_buffer.append" {
            print("[Voice] Sending: \(type)")
        }

        webSocket?.send(.string(string)) { error in
            if let error = error {
                print("[Voice] WebSocket send error: \(error)")
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

        // Calculate output frame capacity based on sample rate ratio
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
            print("[Voice] Failed to create output buffer")
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
            print("[Voice] Conversion error: \(error)")
            return
        }

        // Send converted buffer
        processAudioBuffer(outputBuffer)
    }

    private var audioSendCount = 0

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else {
            print("[Voice] No int16 channel data in buffer")
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            print("[Voice] Buffer has 0 frames")
            return
        }

        let data = Data(bytes: channelData[0], count: frameCount * 2)
        let base64 = data.base64EncodedString()

        // Calculate RMS level for debugging (helps detect if audio is silent/noise)
        var sumSquares: Float = 0
        var maxSample: Int16 = 0
        let samples = channelData[0]
        for i in 0..<frameCount {
            let sample = samples[i]
            sumSquares += Float(sample) * Float(sample)
            if abs(sample) > maxSample {
                maxSample = abs(sample)
            }
        }
        let rms = sqrt(sumSquares / Float(frameCount))
        let rmsDb = 20 * log10(max(rms, 1) / 32768.0)

        audioSendCount += 1
        if audioSendCount % 50 == 1 {
            print("[Voice] Sending audio chunk #\(audioSendCount), size: \(data.count) bytes, RMS: \(String(format: "%.1f", rmsDb))dB, peak: \(maxSample)")
        }

        sendMessage([
            "type": "input_audio_buffer.append",
            "audio": base64,
        ])
    }

    // MARK: - Private Methods - Audio Output

    private func queueAudioPlayback(_ data: Data) {
        playbackBuffer.append(data)

        if !isPlayingAudio {
            playNextAudioChunk()
        }
    }

    private func playNextAudioChunk() {
        guard !playbackBuffer.isEmpty,
              let player = audioPlayer,
              let format = audioFormat else {
            isPlayingAudio = false
            isSpeaking = false
            return
        }

        isPlayingAudio = true
        isSpeaking = true

        let audioData = playbackBuffer.removeFirst()
        let frameCount = AVAudioFrameCount(audioData.count / 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            playNextAudioChunk()
            return
        }

        buffer.frameLength = frameCount
        audioData.withUnsafeBytes { rawBuffer in
            if let baseAddress = rawBuffer.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, audioData.count)
            }
        }

        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                self?.playNextAudioChunk()
            }
        }

        if !audioEngine.isRunning {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback, mode: .default)
                try audioSession.setActive(true)
                try audioEngine.start()
            } catch {
                print("Audio engine start error: \(error)")
            }
        }

        player.play()
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        playbackBuffer.removeAll()
        isPlayingAudio = false
        isSpeaking = false
    }

    // MARK: - Private Methods - Session Management

    private func startUsageTimer() {
        stopUsageTimer() // Clear any existing timer
        
        usageTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
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
            print("Failed to end session: \(error)")
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
