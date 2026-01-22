import Foundation
import AVFoundation
import Combine

// MARK: - Voice Service Events

/// Events emitted by the voice service
enum VoiceServiceEvent {
    case connectionStateChanged(VoiceConnectionState)
    case listeningStarted
    case listeningEnded
    case userSpeechStarted
    case userSpeechEnded
    case assistantSpeechStarted
    case assistantSpeechEnded
    case bargeInTriggered      // User interrupted AI with speech or tap
    case transcriptUpdated(String)
    case quotaUpdated(Double)
    case emotionDetected(EmotionAnalyzer.EmotionResult)  // Emotion detected from voice
    case error(VoiceError)
}

/// Delegate protocol for receiving voice service events
@MainActor
protocol VoiceServiceDelegate: AnyObject {
    func voiceService(_ service: any VoiceServiceProtocol, didEmit event: VoiceServiceEvent)
}

// MARK: - Connection State

/// Connection state for voice service
enum VoiceConnectionState: Equatable, CustomStringConvertible {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reconnecting: return "reconnecting"
        case .error(let message): return "error(\(message))"
        }
    }
}

/// Protocol abstraction for voice service implementations
/// Enables testing and dependency injection
@MainActor
protocol VoiceServiceProtocol: ObservableObject {

    // MARK: - Delegate

    var delegate: VoiceServiceDelegate? { get set }

    // MARK: - Published State

    var connectionState: VoiceConnectionState { get }
    var isListening: Bool { get }
    var isSpeaking: Bool { get }
    var isUserSpeaking: Bool { get }
    var transcribedText: String { get }
    var minutesRemaining: Double { get }
    var currentVoice: GrokVoice { get }
    var availableVoices: [GrokVoice] { get }
    var micLevel: Float { get }
    var playbackLevel: Float { get }
    var isPremium: Bool { get }

    // MARK: - Emotion State

    /// Current detected emotion (nil if no emotion detected or analysis disabled)
    var currentEmotion: EmotionAnalyzer.EmotionResult? { get }

    /// Emotion history for current session
    var emotionHistory: [EmotionSnapshot] { get }

    // MARK: - Connection Management

    /// Connect to voice service
    func connect() async throws

    /// Disconnect from voice service
    func disconnect() async

    // MARK: - Audio Control

    /// Start listening for voice input
    func startListening() throws

    /// Stop listening without requesting response
    func stopListening()

    /// Force commit audio buffer and get response
    func stopListeningAndRespond()

    /// Interrupt assistant playback immediately for barge-in
    func interruptPlayback()

    // MARK: - Voice Settings

    /// Change the AI voice (premium only for non-ara voices)
    func setVoice(_ voice: GrokVoice) async throws

    // MARK: - Emotion Settings

    /// Enable or disable emotion analysis
    func setEmotionAnalysisEnabled(_ enabled: Bool)

    /// Set emotion sensitivity threshold (0.4 - 0.8)
    func setEmotionSensitivity(_ threshold: Double)
}

/// Mock voice service for testing
@MainActor
final class MockVoiceService: VoiceServiceProtocol {

    weak var delegate: VoiceServiceDelegate?

    @Published var connectionState: VoiceConnectionState = .disconnected
    @Published var isListening = false
    @Published var isSpeaking = false
    @Published var isUserSpeaking = false
    @Published var transcribedText = ""
    @Published var minutesRemaining: Double = 10.0
    @Published var currentVoice: GrokVoice = .ara
    @Published var availableVoices: [GrokVoice] = [.ara]
    @Published var micLevel: Float = 0
    @Published var playbackLevel: Float = 0
    @Published var isPremium = false

    // Emotion state
    @Published private(set) var currentEmotion: EmotionAnalyzer.EmotionResult?
    @Published private(set) var emotionHistory: [EmotionSnapshot] = []

    // Test hooks
    var connectCalled = false
    var disconnectCalled = false
    var startListeningCalled = false
    var stopListeningCalled = false
    var interruptPlaybackCalled = false
    var setVoiceCalled = false
    var setEmotionEnabledCalled = false
    var setEmotionSensitivityCalled = false

    var shouldThrowOnConnect = false
    var connectError: Error?

    func connect() async throws {
        connectCalled = true
        if shouldThrowOnConnect {
            throw connectError ?? VoiceError.connectionFailed("Mock error")
        }
        connectionState = .connected
    }

    func disconnect() async {
        disconnectCalled = true
        connectionState = .disconnected
        isListening = false
        isSpeaking = false
        currentEmotion = nil
        emotionHistory = []
    }

    func startListening() throws {
        startListeningCalled = true
        isListening = true
    }

    func stopListening() {
        stopListeningCalled = true
        isListening = false
    }

    func stopListeningAndRespond() {
        isListening = false
    }

    func interruptPlayback() {
        interruptPlaybackCalled = true
        isSpeaking = false
    }

    func setVoice(_ voice: GrokVoice) async throws {
        setVoiceCalled = true
        currentVoice = voice
    }

    func setEmotionAnalysisEnabled(_ enabled: Bool) {
        setEmotionEnabledCalled = true
    }

    func setEmotionSensitivity(_ threshold: Double) {
        setEmotionSensitivityCalled = true
    }

    // Test helpers
    func simulateEmotionDetected(_ result: EmotionAnalyzer.EmotionResult) {
        currentEmotion = result
        let snapshot = EmotionSnapshot(
            emotion: result.emotion,
            confidence: result.confidence,
            allProbabilities: result.allProbabilities,
            timestamp: 0
        )
        emotionHistory.append(snapshot)
        delegate?.voiceService(self, didEmit: .emotionDetected(result))
    }
}
