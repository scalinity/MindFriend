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
    @Published private(set) var isSpeaking = false
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
    private var messageCount = 0

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
            isPremium = tokenResponse.isPremium
            availableVoices = tokenResponse.grokAvailableVoices
            currentVoice = tokenResponse.grokVoice
            sessionId = tokenResponse.sessionId

            try await connectWebSocket(token: tokenResponse.token)

            try await configureSession()

            connectionState = .connected
            sessionStartTime = Date()
            messageCount = 0
        } catch {
            connectionState = .error(error.localizedDescription)
            throw error
        }
    }

    /// Disconnect from voice service
    func disconnect() async {
        stopListening()
        stopPlayback()

        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil

        await endSession()

        connectionState = .disconnected
        transcribedText = ""
        sessionId = nil
        sessionStartTime = nil
    }

    /// Start listening for voice input
    func startListening() throws {
        guard connectionState.isConnected else {
            throw VoiceError.notConnected
        }

        guard !isListening else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try audioSession.setActive(true)

            let inputNode = audioEngine.inputNode
            let recordingFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: true
            )!

            inputNode.installTap(
                onBus: 0,
                bufferSize: 2048,
                format: recordingFormat
            ) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            isListening = true
        } catch {
            throw VoiceError.audioSessionFailed(error.localizedDescription)
        }
    }

    /// Stop listening for voice input
    func stopListening() {
        guard isListening else { return }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        sendMessage([
            "type": "input_audio_buffer.commit",
        ])

        isListening = false
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
            let response = try await supabase.functions.invoke(
                "voice-token",
                options: FunctionInvokeOptions()
            )

            guard let data = response.data else {
                throw VoiceError.tokenGenerationFailed
            }

            if let errorResponse = try? JSONDecoder().decode(VoiceErrorResponse.self, from: data),
               errorResponse.code == "QUOTA_EXCEEDED" {
                throw VoiceError.quotaExceeded
            }

            let tokenResponse = try JSONDecoder().decode(VoiceTokenResponse.self, from: data)
            return tokenResponse
        } catch let error as FunctionsError {
            switch error {
            case .httpError(_, let data):
                if let errorResponse = try? JSONDecoder().decode(VoiceErrorResponse.self, from: data) {
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
            throw VoiceError.tokenGenerationFailed
        }
    }

    private func connectWebSocket(token: String) async throws {
        let url = URL(string: "wss://api.x.ai/v1/realtime?token=\(token)")!

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300

        urlSession = URLSession(configuration: configuration)
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()

        receiveMessages()
    }

    private func configureSession() async throws {
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "instructions": voiceInstructions,
                "voice": currentVoice.rawValue,
                "turn_detection": [
                    "type": "server_vad",
                ],
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": Int(sampleRate),
                        ],
                    ],
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": Int(sampleRate),
                        ],
                    ],
                ],
            ],
        ]

        sendMessage(config)
    }

    // MARK: - Private Methods - WebSocket

    private func receiveMessages() {
        webSocket?.receive { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let message):
                Task { @MainActor in
                    self.handleWebSocketMessage(message)
                }
                self.receiveMessages()
            case .failure(let error):
                Task { @MainActor in
                    if self.connectionState.isConnected {
                        self.connectionState = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            guard let data = text.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                return
            }

            handleEvent(type: type, json: json)
        case .data(let data):
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else {
                return
            }

            handleEvent(type: type, json: json)
        @unknown default:
            break
        }
    }

    private func handleEvent(type: String, json: [String: Any]) {
        switch type {
        case "session.created", "session.updated":
            if connectionState == .connecting {
                connectionState = .connected
            }

        case "input_audio_buffer.speech_started":
            isListening = true
            stopPlayback()

        case "input_audio_buffer.speech_stopped":
            isListening = false

        case "response.output_audio.delta":
            if let delta = json["delta"] as? String,
               let audioData = Data(base64Encoded: delta) {
                queueAudioPlayback(audioData)
            }

        case "response.output_audio_transcript.delta":
            if let delta = json["delta"] as? String {
                transcribedText += delta
            }

        case "response.done":
            messageCount += 1
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self.transcribedText = ""
                }
            }

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                connectionState = .error(message)
            }

        default:
            break
        }
    }

    private func sendMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else {
            return
        }

        webSocket?.send(.string(string)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    // MARK: - Private Methods - Audio Input

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.int16ChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        let data = Data(bytes: channelData[0], count: frameCount * 2)
        let base64 = data.base64EncodedString()

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

    private func endSession() async {
        guard let sessionId = sessionId,
              let startTime = sessionStartTime else {
            return
        }

        let durationSeconds = Int(Date().timeIntervalSince(startTime))

        do {
            _ = try await supabase.functions.invoke(
                "voice-session-end",
                options: FunctionInvokeOptions(
                    body: [
                        "session_id": sessionId,
                        "duration_seconds": durationSeconds,
                        "messages_count": messageCount,
                        "was_quota_limited": false,
                    ]
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
