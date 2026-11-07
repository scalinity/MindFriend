import Foundation
import AVFoundation
import Combine
import Supabase
import OSLog
import UIKit

// MARK: - Seams
//
// These protocols exist so the lifecycle can be exercised deterministically without a microphone,
// a socket or a server. Production types conform below; tests inject fakes.

/// Authenticated identity at the moment of the call.
struct VoiceAuthSnapshot: Equatable, Sendable {
    let userID: UUID
    let accessToken: String
}

/// Admission body for the fixed-host `test-auth-diagnostic` relay (new contract). The server owns the
/// packet and the actual provider route. The client never sends instructions or context text.
struct VoiceAdmissionRequestBody: Encodable, Equatable, Sendable {
    static let schemaVersion = 1

    let transport: String
    let schemaVersion: Int
    let expectedOwner: UUID
    let supportSessionID: UUID
    let conversationID: UUID
    let contextScope: String
    let expectedPrivacyRevision: Int64?

    init(binding: VoiceSupportBinding) {
        transport = "relay"
        schemaVersion = Self.schemaVersion
        expectedOwner = binding.ownerUUID
        supportSessionID = binding.supportSessionUUID
        conversationID = binding.conversationUUID
        contextScope = binding.scope.rawValue
        expectedPrivacyRevision = binding.privacyRevision
    }

    enum CodingKeys: String, CodingKey {
        case transport
        case schemaVersion = "schema_version"
        case expectedOwner = "expected_owner"
        case supportSessionID = "support_session_id"
        case conversationID = "conversation_id"
        case contextScope = "context_scope"
        case expectedPrivacyRevision = "expected_privacy_revision"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(transport, forKey: .transport)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        // Lower-case so server-side string comparison with the auth user id cannot differ by case.
        try container.encode(expectedOwner.uuidString.lowercased(), forKey: .expectedOwner)
        try container.encode(supportSessionID.uuidString.lowercased(), forKey: .supportSessionID)
        try container.encode(conversationID.uuidString.lowercased(), forKey: .conversationID)
        try container.encode(contextScope, forKey: .contextScope)
        try container.encodeIfPresent(expectedPrivacyRevision, forKey: .expectedPrivacyRevision)
    }
}

/// One admission answer: the existing token response plus the nested `voice_context` outcome.
/// `voiceContext` is either a structurally valid claim or the narrow reason it is unusable; it is never
/// derived from top-level fields.
struct VoiceAdmission: Sendable {
    let token: VoiceTokenResponse
    let voiceContext: Result<VoiceContextClaim, VoiceSupportAccessError>
}

struct VoiceSessionEndRequest: Encodable, Equatable, Sendable {
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

/// Server calls made on behalf of one voice session. Every call carries an explicit token so the
/// caller decides which owner it acts for; nothing here reads ambient auth implicitly.
@MainActor
protocol VoiceRelayBackend: AnyObject {
    func authSnapshot() async throws -> VoiceAuthSnapshot
    func admit(_ body: VoiceAdmissionRequestBody, authorization token: String) async throws -> VoiceAdmission
    /// Reports honestly: `.confirmed` only for a successful server answer, otherwise `.unconfirmed`.
    func endSession(_ request: VoiceSessionEndRequest, authorization token: String) async -> VoiceAccountingResult
    /// Persists the preferred voice. When `expectedOwner` is set and the ambient account differs,
    /// nothing is written.
    func saveVoicePreference(_ voice: GrokVoice, expectedOwner: UUID?) async throws
}

/// Fixed-host relay socket.
@MainActor
protocol VoiceRelayTransport: AnyObject {
    var onMessage: ((URLSessionWebSocketTask.Message) -> Void)? { get set }
    var onConnectionLost: ((_ sessionLimitReached: Bool) -> Void)? { get set }
    func connect(sessionId: String, userToken: String) async throws
    func disconnect()
    func send(_ message: [String: Any])
}

extension VoiceWebSocketManager: VoiceRelayTransport {}

@MainActor
protocol VoiceCaptureControlling: AnyObject {
    /// Delivered synchronously on the main actor, stamped with the generation that produced it.
    var onAudioData: ((Data, VoiceCaptureGeneration) -> Void)? { get set }
    var onMicLevelUpdate: ((Float, VoiceCaptureGeneration) -> Void)? { get set }
    /// Returns the generation of this capture start.
    @discardableResult
    func startCapture() throws -> VoiceCaptureGeneration
    func stopCapture()
    func forceStop()
}

extension VoiceAudioCapture: VoiceCaptureControlling {}

@MainActor
protocol VoicePlaybackControlling: AnyObject {
    var onPlaybackStart: (() -> Void)? { get set }
    var onPlaybackEnd: (() -> Void)? { get set }
    var onPlaybackLevelUpdate: ((Float) -> Void)? { get set }
    var lastPlaybackEndTime: Date? { get }
    var echoCooldownSeconds: TimeInterval { get }
    func queueAudioChunk(_ audioData: Data)
    func stop()
}

extension VoiceAudioPlayback: VoicePlaybackControlling {}

// MARK: - Production backend

/// Refuses every redirect, so a bearer token can never be forwarded to a host other than the one the
/// request was built for.
final class VoiceNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Relay calls made on behalf of one voice session.
///
/// `admit` and `endSession` are raw fixed-host requests that carry EXACTLY the token the caller
/// supplies. They deliberately do not go through the Supabase SDK's functions client, which can
/// replace a supplied Authorization header with the ambient session's token. Only `authSnapshot`
/// (and the voice-preference write) use the SDK, where refresh and ownership checks are wanted.
///
/// Errors are mapped to narrow categories; response bodies, tokens and provider text are never logged.
@MainActor
final class SupabaseVoiceRelayBackend: VoiceRelayBackend {
    static let admissionFunction = "test-auth-diagnostic"
    static let sessionEndFunction = "voice-session-end"

    private let supabase: SupabaseClient
    private let session: URLSession
    private let projectURL: URL
    private let anonKey: String

    /// - Parameters:
    ///   - session: Injectable for synthetic wire tests. Defaults to `makeSession()`.
    ///   - projectURL / anonKey: Default to the app configuration; the host is never taken from a response.
    init(
        supabase: SupabaseClient,
        session: URLSession? = nil,
        projectURL: URL = SupabaseConfig.projectURL,
        anonKey: String = SupabaseConfig.anonKey
    ) {
        self.supabase = supabase
        self.session = session ?? Self.makeSession()
        self.projectURL = projectURL
        self.anonKey = anonKey
    }

    /// An ephemeral session that follows no redirects and keeps no cookies or cache.
    /// `extraProtocolClasses` lets tests answer requests in-process without any network.
    nonisolated static func makeSession(extraProtocolClasses: [AnyClass] = []) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if !extraProtocolClasses.isEmpty {
            configuration.protocolClasses = extraProtocolClasses + (configuration.protocolClasses ?? [])
        }
        return URLSession(configuration: configuration, delegate: VoiceNoRedirectDelegate(), delegateQueue: nil)
    }

    /// `https://<configured project host>/functions/v1/<name>`; nothing else is ever contacted.
    nonisolated static func functionURL(_ name: String, projectURL: URL) throws -> URL {
        guard var components = URLComponents(
                url: projectURL.appendingPathComponent("functions/v1/\(name)"),
                resolvingAgainstBaseURL: false
              ), components.scheme == "https", let host = components.host, !host.isEmpty else {
            throw VoiceError.connectionFailed("Invalid secure voice relay session")
        }
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        guard let url = components.url else {
            throw VoiceError.connectionFailed("Invalid secure voice relay URL")
        }
        return url
    }

    /// The exact request that is sent. Exposed so the wire contract can be verified without a network.
    nonisolated static func makeRequest(
        function name: String,
        body: Data,
        token: String,
        projectURL: URL,
        anonKey: String,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard !token.isEmpty else { throw VoiceError.notAuthorized }
        var request = URLRequest(url: try functionURL(name, projectURL: projectURL), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body
        return request
    }

    func authSnapshot() async throws -> VoiceAuthSnapshot {
        do {
            let session = try await supabase.auth.session
            return VoiceAuthSnapshot(userID: session.user.id, accessToken: session.accessToken)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VoiceError.notAuthorized
        }
    }

    func admit(_ body: VoiceAdmissionRequestBody, authorization token: String) async throws -> VoiceAdmission {
        do {
            let request = try Self.makeRequest(
                function: Self.admissionFunction,
                body: try JSONEncoder().encode(body),
                token: token, projectURL: projectURL, anonKey: anonKey, timeout: 30
            )
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw VoiceError.networkUnavailable }
            if http.value(forHTTPHeaderField: "x-relay-error") == "true" { throw VoiceError.networkUnavailable }
            guard (200..<300).contains(http.statusCode) else {
                throw Self.admissionError(status: http.statusCode, code: (try? JSONDecoder().decode(ErrorBody.self, from: data))?.code)
            }
            let tokenResponse = try JSONDecoder().decode(VoiceTokenResponse.self, from: data)
            // Only the nested, versioned object admits a session. Top-level fields are ignored.
            return VoiceAdmission(token: tokenResponse, voiceContext: VoiceContextClaim.parse(responseData: data))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is URLError {
            throw VoiceError.networkUnavailable
        } catch let error as VoiceError {
            throw error
        } catch let error as VoiceSupportAccessError {
            throw error
        } catch {
            throw VoiceError.tokenGenerationFailed
        }
    }

    func endSession(_ request: VoiceSessionEndRequest, authorization token: String) async -> VoiceAccountingResult {
        // Unknown unless the server answers successfully: a thrown error, timeout or non-2xx is
        // `.unconfirmed`. Nothing is retried here and nothing is refunded on the strength of it.
        do {
            let urlRequest = try Self.makeRequest(
                function: Self.sessionEndFunction,
                body: try JSONEncoder().encode(request),
                token: token, projectURL: projectURL, anonKey: anonKey, timeout: 20
            )
            let (_, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse,
                  http.value(forHTTPHeaderField: "x-relay-error") != "true",
                  (200..<300).contains(http.statusCode) else {
                #if DEBUG
                Log.voice.debug("[Voice] Session-end accounting not confirmed")
                #endif
                return .unconfirmed
            }
            return .confirmed
        } catch {
            #if DEBUG
            Log.voice.debug("[Voice] Session-end accounting failed")
            #endif
            return .unconfirmed
        }
    }

    func saveVoicePreference(_ voice: GrokVoice, expectedOwner: UUID?) async throws {
        guard let session = try? await supabase.auth.session else { return }
        if let expectedOwner, session.user.id != expectedOwner { return }

        try await supabase
            .from("voice_settings")
            .upsert([
                "user_id": session.user.id.uuidString,
                "preferred_voice": voice.rawValue,
                "updated_at": ISO8601DateFormatter().string(from: Date()),
            ])
            .execute()
    }

    private struct ErrorBody: Decodable {
        let code: String?
    }

    /// Narrow mapping from an admission failure to a user-safe error.
    nonisolated static func admissionError(status: Int, code: String?) -> Error {
        if let contextError = VoiceSupportAccessError.fromServerCode(code) {
            return contextError
        }
        switch code {
        case "SESSION_LIMIT_REACHED":
            return VoiceError.connectionFailed(VoiceStopReason.sessionLimit.statusMessage ?? "Voice session limit reached.")
        case "QUOTA_EXCEEDED":
            return VoiceError.quotaExceeded
        case "UNAUTHORIZED", "AUTH_REQUIRED":
            return VoiceError.notAuthorized
        case "RATE_LIMITED":
            return VoiceError.networkUnavailable
        default:
            break
        }
        switch status {
        case 403: return VoiceError.quotaExceeded
        case 401: return VoiceError.notAuthorized
        case 429: return VoiceError.networkUnavailable
        default: return VoiceError.tokenGenerationFailed
        }
    }
}

// MARK: - Service

/// Service for real-time voice conversations over the fixed-host relay.
///
/// Lifecycle contract:
/// - Voice only runs against an immutable `VoiceSupportBinding`. There is no unbound or legacy path.
/// - Starting is always an explicit call; nothing connects on presentation.
/// - Every stop goes through `stopNow(_:)`, which halts capture and playback and closes the socket
///   synchronously BEFORE any network await. The microphone is never restarted automatically.
/// - The service is the authority for the explicit mute choice.
/// - Only FINAL transcript events are appended durably, through `VoiceSupportAccess`; "saved" is set
///   only after the access confirms.
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

    /// Transcribed text of user's speech (live caption only; durable turns use typed events).
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

    /// The explicit mute choice. The service is the single authority; views only display it.
    @Published private(set) var isMuted = false

    /// Why the last session stopped. Nil while a session is starting or running.
    @Published private(set) var lastStopReason: VoiceStopReason?

    /// The caption currently on screen, with its actual finality (live, complete, interrupted).
    @Published private(set) var caption: VoiceCaption?

    /// Final transcript events accepted by the access, and those still waiting or rejected.
    @Published private(set) var savedTranscriptCount = 0
    @Published private(set) var unsavedTranscriptCount = 0
    @Published private(set) var rejectedTranscriptCount = 0

    // MARK: - Emotion State (inert)
    //
    // Voice sessions do not analyze emotion and no capability is advertised to the provider or the
    // person. These remain only so existing protocol consumers keep compiling; they are never set.

    @Published private(set) var currentEmotion: EmotionResult?
    @Published private(set) var emotionHistory: [EmotionSnapshot] = []
    @Published private(set) var emotionConfidence: Double = 0

    // MARK: - Delegate / typed events

    weak var delegate: VoiceServiceDelegate?

    /// Receives every typed transcript observation (partial, final, abandoned).
    var transcriptEventHandler: ((VoiceTranscriptEvent) -> Void)?

    // MARK: - Private Properties

    private let backend: any VoiceRelayBackend
    private let microphonePermission: @MainActor () async throws -> Void

    // Specialized components
    private let transport: any VoiceRelayTransport
    private let audioCapture: any VoiceCaptureControlling
    private let audioPlayback: any VoicePlaybackControlling

    // Session tracking
    private var connectionGeneration = UUID()
    private var attemptActive = false
    private var pendingRemoteStops = 0
    /// The only capture generation whose audio may be sent. Cleared before capture is stopped.
    private var captureGeneration: VoiceCaptureGeneration?
    private var captionTracker = VoiceCaptionTracker()
    private var lifecycleSubscriptions = Set<AnyCancellable>()
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
    private var validityTimer: Timer?
    private var invalidationTask: Task<Void, Never>?

    // Bound session
    private struct AdmittedSession {
        let sessionId: String
        let ownerID: UUID
        /// Token captured for the owner at admission; used only to account for this admission.
        let capturedToken: String
    }

    private struct BoundSession {
        let binding: VoiceSupportBinding
        let access: any VoiceSupportAccess
        let journal: VoiceTranscriptJournal
        var assembler: VoiceTranscriptAssembler
    }

    private struct StopSnapshot {
        var admission: AdmittedSession?
        var durationSeconds = 0
        var messageCount = 0
        var binding: VoiceSupportBinding?
        var access: (any VoiceSupportAccess)?
        var journal: VoiceTranscriptJournal?
    }

    private var admission: AdmittedSession?
    /// The verified voice-context claim of the running session (receipt, packet hash, provider route).
    /// Nil whenever no session is admitted. Only identifiers and hashes: never the packet itself.
    private(set) var admittedContext: VoiceContextClaim?
    /// What is known about accounting for the most recent obsolete admission (one that was superseded
    /// while in flight). `.pending` until the server answers; `.unconfirmed` if the call failed.
    private(set) var obsoleteAdmissionAccounting: VoiceAccountingStatus = .notApplicable
    private var obsoleteAccountingToken = UUID()
    private var bound: BoundSession?
    /// Journals of this and earlier sessions that may still hold unsaved finals.
    private var journals: [VoiceTranscriptJournal] = []

    // MARK: - Idle Management

    /// Timer that checks for idle state and ends the relay session
    private var idleDisconnectTimer: Timer?

    /// Last time speech activity was detected
    private var lastSpeechActivityTime: Date?

    /// Threshold in seconds before idle disconnect (90 seconds)
    private let idleDisconnectThreshold: TimeInterval = 90

    // MARK: - Initialization

    convenience init(supabase: SupabaseClient) {
        self.init(
            backend: SupabaseVoiceRelayBackend(supabase: supabase),
            transport: VoiceWebSocketManager(),
            capture: VoiceAudioCapture(),
            playback: VoiceAudioPlayback()
        )
    }

    /// - Parameter microphonePermission: Requests microphone access. Defaults to the system prompt;
    ///   injectable so tests never trigger it.
    init(
        backend: any VoiceRelayBackend,
        transport: any VoiceRelayTransport,
        capture: any VoiceCaptureControlling,
        playback: any VoicePlaybackControlling,
        microphonePermission: (@MainActor () async throws -> Void)? = nil
    ) {
        self.backend = backend
        self.microphonePermission = microphonePermission ?? { try await GrokVoiceService.requestSystemMicrophonePermission() }
        self.transport = transport
        self.audioCapture = capture
        self.audioPlayback = playback
        setupComponentCallbacks()
        observeSystemLifecycle()
    }

    private func observeSystemLifecycle() {
        // All of these converge on the same synchronous stop. None of them restarts the microphone
        // when the interruption ends: starting voice again is always a deliberate act.
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
                MainActor.assumeIsolated { _ = self?.stopNow(.audioInterrupted) }
            }.store(in: &lifecycleSubscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
                MainActor.assumeIsolated { _ = self?.stopNow(.routeLost) }
            }.store(in: &lifecycleSubscriptions)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.stopNow(.audioInterrupted) }
            }.store(in: &lifecycleSubscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.stopNow(.appBackgrounded) }
            }.store(in: &lifecycleSubscriptions)
        NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.stopNow(.deviceLocked) }
            }.store(in: &lifecycleSubscriptions)
    }

    private func setupComponentCallbacks() {
        // WebSocket callbacks
        transport.onMessage = { [weak self] message in
            self?.handleWebSocketMessage(message)
        }

        transport.onConnectionLost = { [weak self] reachedLimit in
            self?.stopNow(reachedLimit ? .sessionLimit : .connectionLost)
        }

        // Audio capture callbacks
        // Capture delivers on the main actor already, so there is no second asynchronous hop that could
        // outlive a mute/stop/restart. Each delivery names the capture generation that produced it and
        // is dropped unless that is the generation currently in use.
        audioCapture.onAudioData = { [weak self] audioData, generation in
            self?.sendAudioData(audioData, generation: generation)
        }

        audioCapture.onMicLevelUpdate = { [weak self] level, generation in
            guard let self, generation == self.captureGeneration, self.isListening else { return }
            self.micLevel = level
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

    // MARK: - Derived state

    /// A stop's remote work (accounting, transcript flush, reconcile) is still running. This is
    /// informational only: it never blocks an explicit new start, which has its own binding.
    var isEnding: Bool { pendingRemoteStops > 0 }

    /// Whether any finals are still waiting to be confirmed.
    var hasUnsavedTranscript: Bool { unsavedTranscriptCount > 0 }

    /// Finals that are pending, in flight or rejected. Leaving with any of them is an explicit choice.
    var hasUnresolvedTranscript: Bool { unsavedTranscriptCount > 0 || rejectedTranscriptCount > 0 }

    /// How long an explicit End waits for noncritical remote work before reporting a truthful state.
    var endRemoteTimeout: TimeInterval = 3

    // MARK: - Connect (bound only)

    /// The unbound path no longer exists: voice always runs against a support session.
    func connect() async throws {
        throw VoiceSupportAccessError.unavailable
    }

    /// Explicit "Start voice". Prepares the support binding through `access` (which may create or
    /// attach the conversation), then connects. Nothing here runs unless the caller invokes it.
    func startVoice(access: any VoiceSupportAccess, startMuted: Bool = false) async throws {
        guard connectionState != .connected && connectionState != .connecting else { return }

        let generation = beginAttempt(startMuted: startMuted)
        do {
            let binding: VoiceSupportBinding
            do {
                binding = try await access.prepare()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as VoiceSupportAccessError {
                throw error
            } catch {
                throw VoiceSupportAccessError.unavailable
            }
            try checkpoint(generation, binding, access)
            try await performConnect(generation: generation, binding: binding, access: access)
        } catch {
            throw await failAttempt(generation, error)
        }
    }

    /// Connect using an already prepared immutable binding.
    func connect(bound binding: VoiceSupportBinding, access: any VoiceSupportAccess, startMuted: Bool = false) async throws {
        guard connectionState != .connected && connectionState != .connecting else { return }
        guard access.isCurrent(binding) else { throw VoiceSupportAccessError.bindingNotCurrent }

        let generation = beginAttempt(startMuted: startMuted)
        do {
            try await performConnect(generation: generation, binding: binding, access: access)
        } catch {
            throw await failAttempt(generation, error)
        }
    }

    private func beginAttempt(startMuted: Bool) -> UUID {
        let generation = UUID()
        connectionGeneration = generation
        attemptActive = true
        connectionState = .connecting
        lastStopReason = nil
        isMuted = startMuted
        // Every explicit connection starts a new relay session.
        isIdleDisconnected = false
        transcribedText = ""
        userTranscribedText = ""
        captionTracker.clear()
        caption = nil
        return generation
    }

    /// Validity point used after every suspension: cancellation, generation, then binding.
    private func checkpoint(_ generation: UUID, _ binding: VoiceSupportBinding, _ access: any VoiceSupportAccess) throws {
        try Task.checkCancellation()
        guard connectionGeneration == generation else { throw CancellationError() }
        guard access.isCurrent(binding) else { throw VoiceSupportAccessError.bindingNotCurrent }
    }

    private func performConnect(generation: UUID, binding: VoiceSupportBinding, access: any VoiceSupportAccess) async throws {
        // 1. Owner check before the microphone prompt and before anything is dispatched.
        var auth = try await backend.authSnapshot()
        try checkpoint(generation, binding, access)
        guard auth.userID == binding.ownerUUID else { throw VoiceSupportAccessError.ownerMismatch }

        try await microphonePermission()
        try checkpoint(generation, binding, access)

        // 2. Admission. The owner is re-verified from a fresh token with no suspension between the
        //    check and the dispatch.
        auth = try await backend.authSnapshot()
        try checkpoint(generation, binding, access)
        guard auth.userID == binding.ownerUUID else { throw VoiceSupportAccessError.ownerMismatch }

        let admitted = try await backend.admit(VoiceAdmissionRequestBody(binding: binding), authorization: auth.accessToken)
        let admittedSession = AdmittedSession(
            sessionId: admitted.token.sessionId,
            ownerID: binding.ownerUUID,
            capturedToken: auth.accessToken
        )
        // Superseded while the admission was in flight (End, Cancel, background, account change, or a
        // newer Start). The stop that took over never saw this admission, so it is accounted for on its
        // own, with the captured owner token. That is bounded and never attached to whatever is running
        // now, and this start refuses promptly instead of waiting on auth or accounting.
        guard connectionGeneration == generation else {
            await accountForObsoleteAdmission(admittedSession)
            throw CancellationError()
        }

        // From here the admission belongs to this attempt: any failure below, including a cancelled task
        // or a stale binding, accounts for it through the central bounded stop.
        admission = admittedSession
        sessionStartTime = Date()
        guard !Task.isCancelled else { throw CancellationError() }
        guard access.isCurrent(binding) else { throw VoiceSupportAccessError.bindingNotCurrent }

        // Fail closed BEFORE any socket or microphone: only a nested, versioned voice_context that
        // matches this binding exactly admits the session. Its absence means a legacy relay, which is
        // never used as a fallback. (The admitted session is still accounted for by the central stop.)
        switch admitted.voiceContext {
        case .failure(let contractError):
            throw contractError
        case .success(let claim):
            try claim.validate(against: binding)
            admittedContext = claim
        }

        let journal = VoiceTranscriptJournal(binding: binding, access: access)
        journal.onChange = { [weak self] in self?.republishTranscriptCounts() }
        journals.append(journal)
        bound = BoundSession(binding: binding, access: access, journal: journal,
                             assembler: VoiceTranscriptAssembler(binding: binding))

        let tokenResponse = admitted.token
        minutesRemaining = tokenResponse.minutesRemaining
        initialMinutesRemaining = tokenResponse.minutesRemaining
        isPremium = tokenResponse.isPremium
        availableVoices = tokenResponse.grokAvailableVoices
        currentVoice = tokenResponse.grokVoice
        startValidityMonitoring(access: access)

        guard let duration = tokenResponse.relayDurationSeconds else {
            throw VoiceError.connectionFailed("Secure voice relay is unavailable. A compatible app and voice server are required.")
        }
        // Secondary client cap. The relay enforces the authoritative session limit.
        sessionLimitTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(duration) * 1_000_000_000) }
            catch { return }
            guard let self, self.connectionGeneration == generation else { return }
            self.stopNow(.sessionLimit)
        }

        // 3. Socket. Same owner check; the fixed-host relay URL is built from configuration only.
        let socketAuth = try await backend.authSnapshot()
        try checkpoint(generation, binding, access)
        guard socketAuth.userID == binding.ownerUUID else { throw VoiceSupportAccessError.ownerMismatch }
        didReceiveSessionCreated = false
        try await transport.connect(sessionId: tokenResponse.sessionId, userToken: socketAuth.accessToken)
        try checkpoint(generation, binding, access)

        // Wait for session.created event from the server
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
        try checkpoint(generation, binding, access)

        // Configure voice/audio/VAD preferences only. Instructions and context are server-owned.
        didReceiveSessionUpdated = false
        configureSession()
        try checkpoint(generation, binding, access)

        // Wait for session.updated confirmation
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
        try checkpoint(generation, binding, access)

        connectionState = .connected
        messageCount = 0

        // Start live usage timer for non-premium users
        if !isPremium {
            startUsageTimer()
        }

        // Start idle disconnect timer
        startIdleTimer()

        // The explicit mute choice decides whether capture starts; nothing else does.
        if !isMuted { try startCaptureNow() }
    }

    /// Accounts for an admission that no attempt owns any more. The call is independent and bounded:
    /// it waits at most `endRemoteTimeout`, records what is known (`pending` until answered,
    /// `unconfirmed` on failure, never success unless the server confirmed), and refunds nothing.
    private func accountForObsoleteAdmission(_ admitted: AdmittedSession) async {
        let token = UUID()
        obsoleteAccountingToken = token
        obsoleteAdmissionAccounting = .pending
        pendingRemoteStops += 1
        let task = Task { @MainActor in
            let answer = await self.performEndSession(admitted, durationSeconds: 0, messagesCount: 0)
            if self.obsoleteAccountingToken == token {
                self.obsoleteAdmissionAccounting = answer == .confirmed ? .confirmed : .unconfirmed
            }
            self.pendingRemoteStops -= 1
        }
        _ = await waitBounded(for: task, seconds: endRemoteTimeout)
    }

    /// Unwinds a failed attempt through the central stop and returns the narrowed error to throw.
    private func failAttempt(_ generation: UUID, _ error: Error) async -> Error {
        let narrowedError = narrowed(error)
        // Another stop already took over this attempt.
        guard connectionGeneration == generation else { return narrowedError }

        let reason: VoiceStopReason
        var message: String?
        if narrowedError is CancellationError {
            reason = .userEnded
        } else if let accessError = narrowedError as? VoiceSupportAccessError, accessError.isContextInvalidation {
            reason = .contextInvalidated
        } else if let voiceError = narrowedError as? VoiceError, case .quotaExceeded = voiceError {
            reason = .quotaReached
        } else {
            reason = .failedToStart
            message = narrowedError.localizedDescription
        }
        _ = await end(reason: reason, failureMessage: message)
        return narrowedError
    }

    private func narrowed(_ error: Error) -> Error {
        switch error {
        case is CancellationError, is VoiceError, is VoiceSupportAccessError:
            return error
        case let error as URLError:
            return error.code == .cancelled ? CancellationError() : VoiceError.networkUnavailable
        default:
            return VoiceError.tokenGenerationFailed
        }
    }

    // MARK: - Central stop

    /// Disconnect from voice service (deliberate stop).
    func disconnect() async {
        await end(reason: .userEnded)
    }

    /// Stops locally and immediately, then waits for the noncritical remote work only up to
    /// `endRemoteTimeout`. A suspended append, reconcile or accounting call can therefore never hold
    /// navigation: the outcome simply reports what is unresolved. Remote work that has not finished
    /// keeps running in the background, is idempotent, and is never reported as done.
    @discardableResult
    func end(reason: VoiceStopReason) async -> VoiceEndOutcome {
        await end(reason: reason, failureMessage: nil)
    }

    private func end(reason: VoiceStopReason, failureMessage: String?) async -> VoiceEndOutcome {
        let (remote, result) = scheduleStop(reason, failureMessage: failureMessage)
        let completed = await waitBounded(for: remote, seconds: endRemoteTimeout)
        republishTranscriptCounts()
        return VoiceEndOutcome(
            unsavedTranscripts: unsavedTranscriptCount,
            rejectedTranscripts: rejectedTranscriptCount,
            remoteWorkCompleted: completed,
            // Honest: still `.pending` unless the session-end call actually answered, and
            // `.unconfirmed` (never success) when it failed or its outcome is unknown.
            accounting: result.accounting
        )
    }

    /// What the stop's session-end call has established so far.
    @MainActor
    private final class StopResult {
        var accounting: VoiceAccountingStatus
        init(accounting: VoiceAccountingStatus) { self.accounting = accounting }
    }

    /// The one stop path. Synchronously halts capture, playback, timers and the socket, then
    /// schedules the remote work (transcript flush and reconcile, session accounting) as an
    /// independent task. Safe to call at any time and from any lifecycle observer; repeated calls are
    /// harmless and never queue behind an earlier stop's remote work.
    @discardableResult
    func stopNow(_ reason: VoiceStopReason, failureMessage: String? = nil) -> Task<Void, Never> {
        scheduleStop(reason, failureMessage: failureMessage).0
    }

    private func scheduleStop(_ reason: VoiceStopReason, failureMessage: String?) -> (Task<Void, Never>, StopResult) {
        let snapshot = haltLocalNow(reason, failureMessage: failureMessage)
        let result = StopResult(accounting: snapshot.admission == nil ? .notApplicable : .pending)

        pendingRemoteStops += 1
        let task = Task { @MainActor in
            await self.finishRemote(snapshot, result: result)
            self.pendingRemoteStops -= 1
        }
        return (task, result)
    }

    private final class BoundedWait {
        var resolved = false
    }

    /// Returns true if `task` finished within the bound, false if the bound elapsed first. The task
    /// itself is never cancelled or abandoned.
    private func waitBounded(for task: Task<Void, Never>, seconds: TimeInterval) async -> Bool {
        let state = BoundedWait()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Task { @MainActor in
                await task.value
                if !state.resolved {
                    state.resolved = true
                    continuation.resume(returning: true)
                }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if !state.resolved {
                    state.resolved = true
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Everything here is synchronous: no network await can delay releasing the microphone.
    private func haltLocalNow(_ reason: VoiceStopReason, failureMessage: String?) -> StopSnapshot {
        let wasActive = attemptActive
        attemptActive = false
        // Obsolete every in-flight connect step and generation-guarded timer.
        connectionGeneration = UUID()

        // Invalidate the capture generation first, so nothing the old capture already queued can be
        // sent, then release hardware: playback before capture so the audio session can deactivate.
        // Capture is unwound unconditionally, so a failed start that never set any flag is cleaned too.
        captureGeneration = nil
        audioPlayback.stop()
        audioCapture.forceStop()
        isListening = false
        isSpeaking = false
        isUserSpeaking = false
        isWaitingForResponse = false
        micLevel = 0
        playbackLevel = 0

        stopUsageTimer()
        stopIdleTimer()
        stopValidityMonitoring()
        sessionLimitTask?.cancel()
        sessionLimitTask = nil
        sessionCreatedTimeoutTask?.cancel()
        sessionCreatedTimeoutTask = nil
        sessionUpdatedTimeoutTask?.cancel()
        sessionUpdatedTimeoutTask = nil
        if let continuation = sessionCreatedContinuation {
            sessionCreatedContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        if let continuation = sessionUpdatedContinuation {
            sessionUpdatedContinuation = nil
            continuation.resume(throwing: CancellationError())
        }

        // Closing the socket is local and non-blocking; no further frames are sent or received.
        transport.disconnect()

        var snapshot = StopSnapshot()
        if let admission {
            let elapsedSeconds = max(0, Date().timeIntervalSince(sessionStartTime ?? Date()))
            snapshot.admission = admission
            snapshot.durationSeconds = Int(elapsedSeconds)
            snapshot.messageCount = messageCount
            if !isPremium { minutesRemaining = max(0, initialMinutesRemaining - elapsedSeconds / 60) }
        }
        if var current = bound {
            // Open turns end here without inventing completion; nothing partial becomes durable.
            for event in current.assembler.abandonOpenTurns() { publish(event) }
            snapshot.binding = current.binding
            snapshot.access = current.access
            snapshot.journal = current.journal
            bound = nil
        }
        admission = nil
        admittedContext = nil
        sessionStartTime = nil
        messageCount = 0
        captionTracker.clear()
        caption = nil

        if wasActive {
            lastStopReason = reason
            if reason.isFailure {
                connectionState = .error(failureMessage ?? reason.statusMessage ?? "Voice session ended.")
            } else {
                connectionState = .disconnected
            }
        }
        transcribedText = ""
        userTranscribedText = ""

        // Clear idle and echo suppression state
        isIdleDisconnected = false
        lastSpeechActivityTime = nil
        playbackStartTime = nil
        echoGateFramesAboveThreshold = 0
        echoGateFramesBelowThreshold = 0

        return snapshot
    }

    /// Transcript durability and session accounting are independent: neither waits for the other, so
    /// a suspended append or reconcile cannot delay accounting, and vice versa.
    private func finishRemote(_ snapshot: StopSnapshot, result: StopResult) async {
        async let transcripts: Void = finishTranscripts(snapshot)
        async let accounting: Void = finishAccounting(snapshot, result: result)
        await transcripts
        await accounting
    }

    private func finishTranscripts(_ snapshot: StopSnapshot) async {
        guard let journal = snapshot.journal, let access = snapshot.access, let binding = snapshot.binding else { return }
        await journal.flush()
        if !journal.isBindingStale { await access.reconcile(binding) }
        republishTranscriptCounts()
    }

    private func finishAccounting(_ snapshot: StopSnapshot, result: StopResult) async {
        guard let admission = snapshot.admission else { return }
        let answer = await performEndSession(admission, durationSeconds: snapshot.durationSeconds, messagesCount: snapshot.messageCount)
        result.accounting = answer == .confirmed ? .confirmed : .unconfirmed
    }

    // MARK: - Audio control

    /// Start listening for voice input. This is a deliberate unmute.
    func startListening() throws {
        guard connectionState.isConnected else { throw VoiceError.notConnected }
        try setMuted(false)
    }

    /// Stop listening without requesting response. This IS the explicit mute.
    func stopListening() {
        try? setMuted(true)
    }

    /// Sets the explicit mute choice. Muting stops capture immediately. Unmuting restarts capture
    /// only through this deliberate call, and only while connected.
    func setMuted(_ muted: Bool) throws {
        if muted {
            isMuted = true
            stopCaptureOnly()
        } else {
            let wasMuted = isMuted
            isMuted = false
            guard connectionState.isConnected else { return }  // capture starts when the connection completes
            do {
                try startCaptureNow()
            } catch {
                // Capture cleaned itself up; the displayed state must match the real one.
                isMuted = wasMuted
                throw error
            }
        }
    }

    /// The single place capture starts (connect, explicit unmute, `startListening`). Every start is
    /// gated on the immutable owner / account epoch / session / conversation / scope / privacy binding
    /// being current RIGHT NOW. A stale binding stops the session before hardware is touched; it never
    /// starts the microphone first and relies on the next frame or tick to notice.
    private func startCaptureNow() throws {
        guard connectionState.isConnected || connectionState == .connecting else { throw VoiceError.notConnected }
        guard attemptActive, let bound else { throw VoiceError.notConnected }
        guard bound.access.isCurrent(bound.binding) else {
            stopNow(.contextInvalidated)
            throw VoiceSupportAccessError.bindingNotCurrent
        }
        guard !isListening else { return }
        captureGeneration = try audioCapture.startCapture()
        isListening = true
    }

    private func stopCaptureOnly() {
        // Invalidate before stopping, so audio the old capture already produced cannot be sent after a
        // later unmute starts a new capture.
        captureGeneration = nil
        audioCapture.stopCapture()
        isListening = false
        micLevel = 0
    }

    /// Force commit audio buffer and get response (for edge cases when VAD doesn't trigger)
    /// With server_vad enabled, the server will auto-respond after commit
    func stopListeningAndRespond() {
        guard connectionState.isConnected else { return }
        guard !isWaitingForResponse else { return }

        isWaitingForResponse = true
        transcribedText = ""

        // Just commit - with server_vad + create_response: true, server will auto-respond
        transport.send(["type": "input_audio_buffer.commit"])
        // The server handles everything after commit; audio capture continues for the next turn.
    }

    /// Interrupt assistant playback immediately for barge-in.
    /// Stops audio and cancels any pending server response. It never starts, stops or changes
    /// microphone capture: an explicit mute stays muted, and a stopped microphone stays stopped.
    func interruptPlayback() {
        guard connectionState.isConnected else { return }
        guard isSpeaking || isWaitingForResponse else { return }

        // 1. Stop audio playback immediately
        audioPlayback.stop()

        // 2. Clear any pending response state
        isWaitingForResponse = false
        isSpeaking = false

        // 3. Reset echo gate state for a fresh start
        echoGateFramesAboveThreshold = 0
        echoGateFramesBelowThreshold = 0
        playbackStartTime = nil

        // 4. Stop the server from generating more audio and clear its input buffer
        transport.send(["type": "response.cancel"])
        transport.send(["type": "input_audio_buffer.clear"])

        // 5. Notify delegate of barge-in
        delegate?.voiceService(self, didEmit: .bargeInTriggered)
    }

    /// Change the AI voice (premium only for non-ara voices)
    func setVoice(_ voice: GrokVoice) async throws {
        guard isPremium || voice == .ara else {
            throw VoiceError.premiumRequired
        }

        currentVoice = voice

        if connectionState.isConnected {
            configureSession()
        }

        try await backend.saveVoicePreference(voice, expectedOwner: bound?.binding.ownerUUID)
    }

    // MARK: - Emotion settings (inert)

    /// Retained for source compatibility. Voice sessions do not analyze emotion, so this does nothing.
    func setEmotionAnalysisEnabled(_ enabled: Bool) {}

    /// Retained for source compatibility. Voice sessions do not analyze emotion, so this does nothing.
    func setEmotionSensitivity(_ threshold: Double) {}

    // MARK: - Transcript durability

    /// Re-attempts finals that were not confirmed, then reconciles journals with nothing left pending.
    /// Rejected finals are retried only when the person asks (`includeRejected`).
    func retryUnsavedTranscript(includeRejected: Bool = false) async {
        for journal in journals where journal.unresolvedCount > 0 {
            await journal.retry(includeRejected: includeRejected)
            if !journal.isBindingStale, journal.unsavedCount == 0 {
                await journal.access.reconcile(journal.binding)
            }
        }
        republishTranscriptCounts()
    }

    /// Explicitly gives up finals that were not acknowledged. Nothing is marked saved, and an append
    /// that is already in flight cannot be recalled; this only stops the app holding the text.
    func discardUnresolvedTranscript() {
        for journal in journals { journal.discardUnresolved() }
        republishTranscriptCounts()
    }

    private func republishTranscriptCounts() {
        // Earlier sessions with nothing pending, in flight or rejected are released.
        journals.removeAll { $0 !== bound?.journal && $0.unresolvedCount == 0 }
        savedTranscriptCount = journals.reduce(0) { $0 + $1.savedCount }
        unsavedTranscriptCount = journals.reduce(0) { $0 + $1.unsavedCount }
        rejectedTranscriptCount = journals.reduce(0) { $0 + $1.rejectedCount }
    }

    private func publish(_ event: VoiceTranscriptEvent) {
        transcriptEventHandler?(event)
        // The caption follows typed finality, never the transient string.
        captionTracker.apply(event)
        caption = captionTracker.current
        // Only finals are durable; partials and abandoned turns are display-only.
        if event.finality == .final, let journal = bound?.journal {
            journal.submitFinal(event)
        }
    }

    // MARK: - Private Methods - Connection

    private static func requestSystemMicrophonePermission() async throws {
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

    /// Sends voice/audio/VAD preferences only. Instructions and context are owned by the server for
    /// every session; the client never supplies them.
    private func configureSession() {
        // Using server VAD for natural conversation flow. The server handles speech detection,
        // auto-commit and auto-respond; we stream audio and handle playback/barge-in.
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "modalities": ["audio", "text"],
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

        transport.send(config)
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
                    return true  // Suppress until sustained speech confirmed
                }
            } else {
                // Track consecutive low frames with grace period to avoid audio gaps on brief pauses
                echoGateFramesBelowThreshold += 1

                // Only reset after grace period expires (allows brief pauses in natural speech)
                if echoGateFramesBelowThreshold > echoGateGracePeriodFrames {
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

    private func sendAudioData(_ audioData: Data, generation: VoiceCaptureGeneration) {
        // Only audio from the capture that is running now may reach the socket. Frames produced by an
        // earlier capture (before a mute, stop or restart) are dropped, whenever they are delivered.
        guard generation == captureGeneration, isListening, !isMuted, connectionState.isConnected else { return }
        guard enforceBindingValidity() else { return }

        // Check all echo suppression conditions
        if shouldSuppressAudioForEcho() {
            return
        }

        let base64 = audioData.base64EncodedString()
        transport.send([
            "type": "input_audio_buffer.append",
            "audio": base64,
        ])
    }

    // MARK: - Binding validity

    private func startValidityMonitoring(access: any VoiceSupportAccess) {
        stopValidityMonitoring()
        validityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.enforceBindingValidity()
            }
        }
        if let stream = access.invalidations() {
            invalidationTask = Task { @MainActor [weak self] in
                for await _ in stream {
                    self?.enforceBindingValidity()
                }
            }
        }
    }

    private func stopValidityMonitoring() {
        validityTimer?.invalidate()
        validityTimer = nil
        invalidationTask?.cancel()
        invalidationTask = nil
    }

    /// Stops the session when the account, epoch, session or privacy state no longer matches the
    /// binding. Checked on every incoming event, every outgoing frame, and on a timer.
    @discardableResult
    private func enforceBindingValidity() -> Bool {
        guard attemptActive, let bound else { return true }
        if bound.access.isCurrent(bound.binding) { return true }
        stopNow(.contextInvalidated)
        return false
    }

    // MARK: - Private Methods - WebSocket

    private func handleWebSocketMessage(_ message: URLSessionWebSocketTask.Message) {
        // Message bodies are user content: nothing from them is logged.
        let data: Data
        switch message {
        case .string(let text):
            guard let encoded = text.data(using: .utf8) else { return }
            data = encoded
        case .data(let raw):
            data = raw
        @unknown default:
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            #if DEBUG
            Log.voice.debug("[Voice] Ignored malformed message (\(data.count) bytes)")
            #endif
            return
        }

        handleEvent(type: type, json: json)
    }

    private func handleEvent(type: String, json: [String: Any]) {
        // Events from a stopped or obsolete session are ignored.
        guard attemptActive else { return }
        guard enforceBindingValidity() else { return }

        #if DEBUG
        Log.voice.debug("[Voice] Received event: \(type)")
        #endif

        // Typed transcript identity first, so every provider event passes through one assembler.
        if bound != nil {
            let events = bound?.assembler.ingest(type: type, json: json) ?? []
            for event in events { publish(event) }
        }

        switch type {
        case "session.created", "conversation.created":
            didReceiveSessionCreated = true
            // Cancel timeout task and resume continuation
            sessionCreatedTimeoutTask?.cancel()
            sessionCreatedTimeoutTask = nil
            if let continuation = sessionCreatedContinuation {
                sessionCreatedContinuation = nil
                continuation.resume()
            }

        case "session.updated":
            didReceiveSessionUpdated = true
            // Cancel timeout task and resume continuation
            sessionUpdatedTimeoutTask?.cancel()
            sessionUpdatedTimeoutTask = nil
            if let continuation = sessionUpdatedContinuation {
                sessionUpdatedContinuation = nil
                continuation.resume()
            }

        case "ping":
            // Respond to ping with pong to keep connection alive
            transport.send(["type": "pong"])

        case "input_audio_buffer.speech_started":
            // Reset idle timer on speech activity
            resetIdleTimer()

            // Check if this is a barge-in situation (user speaking while AI is responding)
            let isBargeIn = isSpeaking || isWaitingForResponse

            if isBargeIn {
                // 1. Stop audio playback immediately
                audioPlayback.stop()

                // 2. Cancel the ongoing response from server
                transport.send(["type": "response.cancel"])

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
            // Reset idle timer on speech activity
            resetIdleTimer()

            isUserSpeaking = false
            // With server_vad + create_response: true, the server commits and responds on its own.

        case "conversation.item.input_audio_transcription.updated", "conversation.item.input_audio_transcription.completed":
            // Live caption only. Durable turns come from the typed events above.
            if let transcript = json["transcript"] as? String {
                userTranscribedText = transcript
            }

        case "response.created":
            isWaitingForResponse = true
            isSpeaking = true
            playbackStartTime = Date()  // Track when playback started for echo suppression

        case "response.audio.delta", "response.output_audio.delta":
            if let delta = json["delta"] as? String,
               let audioData = Data(base64Encoded: delta) {
                audioPlayback.queueAudioChunk(audioData)
            }

        case "response.audio_transcript.delta", "response.output_audio_transcript.delta", "response.text.delta":
            if let delta = json["delta"] as? String {
                transcribedText += delta
            }

        case "response.done":
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
                self.captionTracker.clearIfComplete()
                self.caption = self.captionTracker.current
            }

        case "error", "session.error":
            // Provider/server text is never shown or kept; only the category matters.
            let error = json["error"] as? [String: Any] ?? json
            let code = (error["code"] as? String) ?? (json["code"] as? String)
            let message = error["message"] as? String
            let reachedLimit = code == "SESSION_LIMIT_REACHED" || message?.lowercased() == "session limit reached"
            if reachedLimit {
                stopNow(.sessionLimit)
            } else if code == "PRIVACY_LEASE_EXPIRED" {
                // Terminal: the relay could not refresh its privacy lease in time. Nothing resumes.
                stopNow(.privacyLeaseExpired)
            } else if code == "PRIVACY_REVISION_CHANGED" || VoiceSupportAccessError.fromServerCode(code) != nil {
                // Terminal: the privacy revision or voice context changed under the session.
                stopNow(.contextInvalidated)
            } else {
                stopNow(.serverError)
            }

        default:
            break
        }
    }

    // MARK: - Private Methods - Session Management

    private func startUsageTimer() {
        stopUsageTimer() // Clear any existing timer

        // Update every 5 seconds - quota display doesn't need 1s precision
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
    }

    /// Stop the idle disconnect timer
    private func stopIdleTimer() {
        idleDisconnectTimer?.invalidate()
        idleDisconnectTimer = nil
    }

    /// Reset the idle timer when speech activity is detected
    private func resetIdleTimer() {
        lastSpeechActivityTime = Date()
    }

    /// Check if idle threshold has been exceeded
    private func checkIdleTimeout() {
        guard let lastActivity = lastSpeechActivityTime,
              !isIdleDisconnected,
              connectionState.isConnected else { return }

        let elapsed = Date().timeIntervalSince(lastActivity)
        if elapsed >= idleDisconnectThreshold {
            stopNow(.idleTimeout)
        }
    }

    private func updateMinutesRemaining() {
        guard let startTime = sessionStartTime else { return }

        let elapsedSeconds = Date().timeIntervalSince(startTime)
        let elapsedMinutes = elapsedSeconds / 60.0
        minutesRemaining = max(0, initialMinutesRemaining - elapsedMinutes)

        // Stop session when the local allowance estimate is exhausted. The server stays authoritative.
        if minutesRemaining <= 0 {
            stopNow(.quotaReached)
        }
    }

    /// Accounts for an admitted session on behalf of its owner. Uses the ambient token only when it
    /// still belongs to that owner; otherwise the token captured at admission, never another account's.
    /// Returns what the server established; `.unconfirmed` is never promoted to success.
    private func performEndSession(_ admission: AdmittedSession, durationSeconds: Int, messagesCount: Int) async -> VoiceAccountingResult {
        var token = admission.capturedToken
        if let ambient = try? await backend.authSnapshot(), ambient.userID == admission.ownerID {
            token = ambient.accessToken
        }
        return await backend.endSession(
            VoiceSessionEndRequest(
                sessionId: admission.sessionId,
                durationSeconds: durationSeconds,
                messagesCount: messagesCount,
                wasQuotaLimited: false
            ),
            authorization: token
        )
    }
}
