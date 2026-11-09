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
    case idleDisconnected      // WebSocket closed due to inactivity
    case transcriptUpdated(String)
    case userTranscriptUpdated(String)  // User's speech transcribed
    case quotaUpdated(Double)
    case emotionDetected(EmotionResult)  // Emotion detected from voice
    case error(VoiceError)
}

/// Delegate protocol for receiving voice service events
@MainActor
protocol VoiceServiceDelegate: AnyObject {
    func voiceService(_ service: any VoiceServiceProtocol, didEmit event: VoiceServiceEvent)
}

// MARK: - Stop Reasons

/// Why a voice session stopped. Every reason goes through the same central stop: capture and
/// playback are halted synchronously before any network await, and the microphone is never
/// restarted automatically afterwards.
enum VoiceStopReason: String, Equatable, Sendable {
    // Deliberate
    case userEnded
    case switchedToText
    // Lifecycle / system
    case appBackgrounded
    case deviceLocked
    case audioInterrupted
    case routeLost
    // Account / context
    case accountChanged
    case contextInvalidated
    /// The relay's privacy lease expired before it could be refreshed (PRIVACY_LEASE_EXPIRED).
    case privacyLeaseExpired
    // Limits and transport
    case sessionLimit
    case idleTimeout
    case quotaReached
    case connectionLost
    case serverError
    case failedToStart

    /// The person chose to stop; there is nothing to explain.
    var isDeliberate: Bool { self == .userEnded || self == .switchedToText }

    /// The session ended without the person asking. Shown as "interrupted" with an explicit restart.
    var isInterruption: Bool { !isDeliberate && self != .failedToStart }

    /// Plain-language status. Never contains provider or server text.
    var statusMessage: String? {
        switch self {
        case .userEnded, .switchedToText, .failedToStart:
            return nil
        case .sessionLimit:
            return "Voice session ended. Sessions last up to two minutes, or your remaining monthly allowance. Continue by text or start voice again."
        case .quotaReached:
            return "Monthly voice quota reached. Your three free minutes have been used. Premium includes unlimited monthly minutes, with sessions up to two minutes."
        case .accountChanged, .contextInvalidated:
            return "Voice stopped because the account or privacy settings changed. Continue by text or start voice again."
        case .privacyLeaseExpired:
            return "Voice stopped because privacy settings couldn't be confirmed in time. Continue by text or start voice again."
        case .appBackgrounded, .deviceLocked, .audioInterrupted, .routeLost, .idleTimeout, .connectionLost, .serverError:
            return "Voice session paused. Continue by text or start voice again."
        }
    }

    /// The owner, account or context changed under whatever was pending. Deliberate stops (End, text
    /// switch) are the leave itself, so they never retire a pending leave decision; these do.
    var invalidatesPendingLeave: Bool {
        switch self {
        case .accountChanged, .contextInvalidated, .privacyLeaseExpired:
            return true
        default:
            return false
        }
    }

    /// Whether the transport state should surface as an error rather than a plain disconnect.
    var isFailure: Bool {
        switch self {
        case .quotaReached, .connectionLost, .serverError, .failedToStart:
            return true
        default:
            return false
        }
    }
}

// MARK: - End outcome

/// What the server told us about accounting for an admitted session's usage. Accounting is
/// "unknown unless confirmed": a failure, timeout or missing answer is never reported as success, and
/// nothing is refunded locally on the strength of it.
enum VoiceAccountingStatus: Equatable, Sendable {
    /// No session was admitted, so there was nothing to account for.
    case notApplicable
    /// The session-end call has not finished (still in flight or waiting on auth).
    case pending
    /// The server answered the session-end call successfully.
    case confirmed
    /// The call failed or its outcome is unknown. The server may or may not have recorded the usage.
    case unconfirmed
}

/// Result of one session-end call.
enum VoiceAccountingResult: Equatable, Sendable {
    case confirmed
    case unconfirmed
}

/// What an explicit End / text switch leaves behind once the LOCAL stop has happened and the
/// bounded wait for noncritical remote work has finished.
struct VoiceEndOutcome: Equatable, Sendable {
    /// Finals not yet acknowledged (pending or still in flight). Never counted as saved.
    var unsavedTranscripts: Int
    /// Finals the access permanently rejected. Retained in memory until retried or discarded.
    var rejectedTranscripts: Int
    /// True when the remote tasks (transcript flush, reconcile, session-end call) all ended within
    /// the bound. This says nothing about success: see `accounting`. False means they keep running in
    /// the background, are idempotent, and are not reported as done.
    var remoteWorkCompleted: Bool
    /// The honest state of session accounting for the admitted session.
    var accounting: VoiceAccountingStatus = .notApplicable

    var hasUnresolvedTranscript: Bool { unsavedTranscripts > 0 || rejectedTranscripts > 0 }
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
    var isIdleDisconnected: Bool { get }  // WebSocket closed due to idle timeout
    var transcribedText: String { get }
    var userTranscribedText: String { get }  // User's transcribed speech
    var minutesRemaining: Double { get }
    var currentVoice: GrokVoice { get }
    var availableVoices: [GrokVoice] { get }
    var micLevel: Float { get }
    var playbackLevel: Float { get }
    var isPremium: Bool { get }

    /// The service is the single authority for the explicit mute choice; views display it.
    var isMuted: Bool { get }

    /// Why the last session stopped (nil while a session is starting or running).
    var lastStopReason: VoiceStopReason? { get }

    /// Receives typed transcript observations (partial, final, abandoned) as they occur.
    var transcriptEventHandler: ((VoiceTranscriptEvent) -> Void)? { get set }

    /// The caption on screen with its actual finality (live, complete, interrupted).
    var caption: VoiceCaption? { get }

    /// Finals that are pending, in flight or rejected. Leaving without resolving them is a choice.
    var hasUnresolvedTranscript: Bool { get }
    var unsavedTranscriptCount: Int { get }
    var rejectedTranscriptCount: Int { get }

    // MARK: - Emotion State

    /// Current detected emotion (nil if no emotion detected or analysis disabled)
    var currentEmotion: EmotionResult? { get }

    /// Emotion history for current session
    var emotionHistory: [EmotionSnapshot] { get }

    // MARK: - Connection Management

    /// Unbound connect is intentionally unsupported: voice always runs against a support session.
    /// Use `startVoice(access:startMuted:)` or `connect(bound:access:startMuted:)`.
    func connect() async throws

    /// Explicit "Start voice": prepares the support binding through `access`, then connects.
    func startVoice(access: any VoiceSupportAccess, startMuted: Bool) async throws

    /// Connect using an already prepared immutable binding.
    func connect(bound binding: VoiceSupportBinding, access: any VoiceSupportAccess, startMuted: Bool) async throws

    /// Disconnect from voice service
    func disconnect() async

    /// Central stop. Halts capture and playback and closes the socket synchronously first. Remote
    /// work (transcript flush, reconcile, session accounting) then runs independently and this call
    /// waits for it only up to a bound, so navigation is never held by a suspended remote call.
    /// Never restarts the microphone.
    @discardableResult
    func end(reason: VoiceStopReason) async -> VoiceEndOutcome

    /// Explicitly gives up finals that were not acknowledged. Never marks anything saved.
    func discardUnresolvedTranscript()

    /// Re-attempts finals that were not acknowledged. Rejected ones are retried only when asked.
    func retryUnsavedTranscript(includeRejected: Bool) async

    // MARK: - Audio Control

    /// Start listening for voice input (also clears an explicit mute).
    func startListening() throws

    /// Stop listening without requesting response (this IS the explicit mute).
    func stopListening()

    /// Set the explicit mute choice. Unmuting restarts capture only on this deliberate call.
    func setMuted(_ muted: Bool) throws

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
    @Published var isIdleDisconnected = false
    @Published var transcribedText = ""
    @Published var userTranscribedText: String = ""  // User's transcribed speech
    @Published var minutesRemaining: Double = 10.0
    @Published var currentVoice: GrokVoice = .ara
    @Published var availableVoices: [GrokVoice] = [.ara]
    @Published var micLevel: Float = 0
    @Published var playbackLevel: Float = 0
    @Published var isPremium = false
    @Published var isMuted = false
    @Published var lastStopReason: VoiceStopReason?
    @Published var caption: VoiceCaption?
    var hasUnresolvedTranscript = false
    var unsavedTranscriptCount = 0
    var rejectedTranscriptCount = 0
    var transcriptEventHandler: ((VoiceTranscriptEvent) -> Void)?

    // Emotion state
    @Published private(set) var currentEmotion: EmotionResult?
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

    var startVoiceCalled = false
    var endReasons: [VoiceStopReason] = []
    /// What `end(reason:)` reports, and an optional suspension point inside it (a deferred End).
    var endOutcome = VoiceEndOutcome(unsavedTranscripts: 0, rejectedTranscripts: 0, remoteWorkCompleted: true)
    var endGate: (() async -> Void)?

    func connect() async throws {
        connectCalled = true
        if shouldThrowOnConnect {
            throw connectError ?? VoiceError.connectionFailed("Mock error")
        }
        connectionState = .connected
    }

    func startVoice(access: any VoiceSupportAccess, startMuted: Bool) async throws {
        startVoiceCalled = true
        isMuted = startMuted
        lastStopReason = nil
        if shouldThrowOnConnect {
            throw connectError ?? VoiceError.connectionFailed("Mock error")
        }
        connectionState = .connected
        isListening = !startMuted
    }

    func connect(bound binding: VoiceSupportBinding, access: any VoiceSupportAccess, startMuted: Bool) async throws {
        try await startVoice(access: access, startMuted: startMuted)
    }

    @discardableResult
    func end(reason: VoiceStopReason) async -> VoiceEndOutcome {
        endReasons.append(reason)
        lastStopReason = reason
        await disconnect()
        if let endGate { await endGate() }
        return endOutcome
    }

    func discardUnresolvedTranscript() {
        hasUnresolvedTranscript = false
        unsavedTranscriptCount = 0
        rejectedTranscriptCount = 0
    }

    func retryUnsavedTranscript(includeRejected: Bool) async {}

    func disconnect() async {
        disconnectCalled = true
        connectionState = .disconnected
        isListening = false
        isSpeaking = false
        isIdleDisconnected = false
        currentEmotion = nil
        emotionHistory = []
    }

    func startListening() throws {
        startListeningCalled = true
        isMuted = false
        isListening = true
    }

    func stopListening() {
        stopListeningCalled = true
        isMuted = true
        isListening = false
    }

    func setMuted(_ muted: Bool) throws {
        if muted { stopListening() } else { try startListening() }
    }

    func stopListeningAndRespond() {
        isListening = false
    }

    func interruptPlayback() {
        interruptPlaybackCalled = true
        isSpeaking = false
        // Interrupting playback never changes the explicit mute choice or capture state.
    }

    func setVoice(_ voice: GrokVoice) async throws {
        setVoiceCalled = true
        currentVoice = voice
    }

    func setEmotionAnalysisEnabled(_ enabled: Bool) {
        // Retained for source compatibility only; voice sessions do not analyze emotion.
        setEmotionEnabledCalled = true
    }

    func setEmotionSensitivity(_ threshold: Double) {
        setEmotionSensitivityCalled = true
    }

    // Test helpers
    func simulateEmotionDetected(_ result: EmotionResult) {
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
