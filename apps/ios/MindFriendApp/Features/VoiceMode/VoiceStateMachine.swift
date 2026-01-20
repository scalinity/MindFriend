import Foundation

// MARK: - Voice State Machine

/// Deterministic state machine for Voice Mode
/// Provides clear state transitions and prevents invalid states
struct VoiceStateMachine {

    // MARK: - State

    enum State: Equatable, Hashable {
        case idle
        case requestingPermissions
        case connecting
        case ready
        case listening
        case userSpeaking
        case endOfUtterance
        case sending
        case thinking
        case processing
        case speaking
        case bargeIn
        case muted
        case reconnecting
        case error(String)
        case ended

        // MARK: - Orb Color Mapping

        /// Maps state to orb color category
        var orbColor: OrbColor {
            switch self {
            case .idle, .ended:
                return .inactive
            case .requestingPermissions, .connecting:
                return .connecting
            case .ready, .listening:
                return .ready
            case .userSpeaking, .bargeIn:
                return .userSpeaking
            case .endOfUtterance, .sending, .thinking, .processing:
                return .thinking
            case .speaking:
                return .aiSpeaking
            case .muted:
                return .muted
            case .reconnecting:
                return .reconnecting
            case .error:
                return .error
            }
        }

        // MARK: - Orb Icon

        /// SF Symbol name for the current state
        var orbIcon: String {
            switch self {
            case .idle:
                return "mic.fill"
            case .requestingPermissions:
                return "lock.fill"
            case .connecting, .reconnecting:
                return "antenna.radiowaves.left.and.right"
            case .ready:
                return "ear"
            case .listening:
                return "ear.fill"
            case .userSpeaking, .bargeIn:
                return "waveform"
            case .endOfUtterance, .sending:
                return "arrow.up.circle"
            case .thinking, .processing:
                return "brain"
            case .speaking:
                return "speaker.wave.2.fill"
            case .muted:
                return "mic.slash.fill"
            case .error:
                return "exclamationmark.triangle.fill"
            case .ended:
                return "checkmark.circle.fill"
            }
        }

        // MARK: - Activity Status

        /// Whether the state represents an active session
        var isActive: Bool {
            switch self {
            case .idle, .ended, .error:
                return false
            default:
                return true
            }
        }

        /// Whether audio capture should be running
        var shouldCaptureAudio: Bool {
            switch self {
            case .ready, .listening, .userSpeaking, .bargeIn, .speaking:
                return true
            default:
                return false
            }
        }

        /// Whether audio playback might be active
        var isPlaybackState: Bool {
            switch self {
            case .speaking:
                return true
            default:
                return false
            }
        }

        // MARK: - Status Text

        /// Human-readable status description
        var statusText: String {
            switch self {
            case .idle:
                return "Tap to start"
            case .requestingPermissions:
                return "Requesting permissions..."
            case .connecting:
                return "Connecting..."
            case .ready:
                return "Ready to listen"
            case .listening:
                return "Listening..."
            case .userSpeaking:
                return "Listening..."
            case .endOfUtterance:
                return "Processing..."
            case .sending:
                return "Sending..."
            case .thinking:
                return "Thinking..."
            case .processing:
                return "Processing..."
            case .speaking:
                return "Speaking..."
            case .bargeIn:
                return "Listening..."
            case .muted:
                return "Muted"
            case .reconnecting:
                return "Reconnecting..."
            case .error(let message):
                return "Error: \(message)"
            case .ended:
                return "Session ended"
            }
        }

        /// Whether interruption (barge-in) is allowed in this state
        var allowsBargeIn: Bool {
            switch self {
            case .speaking, .thinking, .processing:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Orb Color

    /// Color categories for orb visualization
    enum OrbColor: Equatable, Hashable {
        case inactive
        case connecting
        case ready
        case userSpeaking
        case thinking
        case aiSpeaking
        case interrupted
        case muted
        case reconnecting
        case error
    }

    // MARK: - Event

    enum Event: Equatable {
        // UI Events
        case tapStart
        case tapEnd
        case tapInterrupt
        case toggleMute
        case toggleCaptions
        case selectVoice(String)

        // Permission Events
        case micPermissionGranted
        case micPermissionDenied
        case speechPermissionGranted
        case speechPermissionDenied

        // VAD Events
        case speechStart
        case speechEnd
        case endOfUtteranceDetected

        // Transport Events
        case connected
        case disconnected
        case serverTranscriptDelta(String)
        case serverAudioChunk(Data)
        case serverThinking
        case serverResponseStart
        case serverResponseDone
        case serverError(String)

        // Audio Events
        case audioPlaybackStarted
        case audioPlaybackFinished

        // System Events
        case audioInterruptedBegin
        case audioInterruptedEnd
        case routeChanged
        case sessionTimeout
        case quotaExceeded
    }

    // MARK: - Properties

    private(set) var state: State
    private(set) var isMuted: Bool
    private(set) var captionsEnabled: Bool
    private(set) var selectedVoiceId: String?

    // MARK: - Initialization

    init(
        initialState: State = .idle,
        isMuted: Bool = false,
        captionsEnabled: Bool = true,
        selectedVoiceId: String? = nil
    ) {
        self.state = initialState
        self.isMuted = isMuted
        self.captionsEnabled = captionsEnabled
        self.selectedVoiceId = selectedVoiceId
    }

    // MARK: - Reducer

    /// Processes an event and returns the new state
    /// This is a pure function - given the same state and event, it always produces the same result
    mutating func send(_ event: Event) -> State {
        let previousState = state

        switch (state, event) {

        // MARK: - Idle State Transitions

        case (.idle, .tapStart):
            state = .requestingPermissions

        // MARK: - Permission State Transitions

        case (.requestingPermissions, .micPermissionGranted):
            state = .connecting

        case (.requestingPermissions, .micPermissionDenied):
            state = .error("Microphone access required")

        // MARK: - Connecting State Transitions

        case (.connecting, .connected):
            state = .ready

        case (.connecting, .disconnected):
            state = .error("Connection failed")

        case (.connecting, .serverError(let message)):
            state = .error(message)

        // MARK: - Ready State Transitions

        case (.ready, .speechStart):
            if !isMuted {
                state = .userSpeaking
            }

        case (.ready, .tapEnd):
            state = .ended

        case (.ready, .toggleMute):
            isMuted.toggle()
            state = isMuted ? .muted : .ready

        case (.ready, .disconnected):
            state = .reconnecting

        // MARK: - Listening State Transitions

        case (.listening, .speechStart):
            if !isMuted {
                state = .userSpeaking
            }

        case (.listening, .tapEnd):
            state = .ended

        case (.listening, .toggleMute):
            isMuted.toggle()
            state = isMuted ? .muted : .listening

        case (.listening, .disconnected):
            state = .reconnecting

        // MARK: - User Speaking State Transitions

        case (.userSpeaking, .speechEnd):
            state = .endOfUtterance

        case (.userSpeaking, .toggleMute):
            isMuted.toggle()
            if isMuted {
                state = .muted
            }

        case (.userSpeaking, .tapEnd):
            state = .ended

        case (.userSpeaking, .disconnected):
            state = .reconnecting

        // MARK: - End of Utterance State Transitions

        case (.endOfUtterance, .serverThinking):
            state = .thinking

        case (.endOfUtterance, .serverResponseStart):
            state = .thinking

        case (.endOfUtterance, .disconnected):
            state = .reconnecting

        // MARK: - Sending State Transitions

        case (.sending, .serverThinking):
            state = .thinking

        case (.sending, .serverResponseStart):
            state = .thinking

        case (.sending, .disconnected):
            state = .reconnecting

        case (.sending, .serverError(let message)):
            state = .error(message)

        // MARK: - Thinking State Transitions

        case (.thinking, .serverAudioChunk):
            state = .speaking

        case (.thinking, .serverResponseDone):
            state = .ready

        case (.thinking, .speechStart):
            // Barge-in while thinking
            state = .bargeIn

        case (.thinking, .tapInterrupt):
            state = .bargeIn

        case (.thinking, .disconnected):
            state = .reconnecting

        case (.thinking, .serverError(let message)):
            state = .error(message)

        // MARK: - Processing State Transitions

        case (.processing, .serverAudioChunk):
            state = .speaking

        case (.processing, .serverResponseDone):
            state = .ready

        case (.processing, .speechStart):
            state = .bargeIn

        case (.processing, .tapInterrupt):
            state = .bargeIn

        case (.processing, .disconnected):
            state = .reconnecting

        // MARK: - Speaking State Transitions

        case (.speaking, .speechStart):
            // Barge-in: user started speaking while AI is speaking
            state = .bargeIn

        case (.speaking, .tapInterrupt):
            state = .bargeIn

        case (.speaking, .audioPlaybackFinished):
            state = .ready

        case (.speaking, .serverResponseDone):
            // Wait for audio playback to finish
            break

        case (.speaking, .disconnected):
            state = .reconnecting

        case (.speaking, .toggleMute):
            isMuted.toggle()
            if isMuted {
                state = .muted
            }

        // MARK: - Barge-In State Transitions

        case (.bargeIn, .audioPlaybackFinished):
            // Playback stopped, check if user is speaking
            state = .listening

        case (.bargeIn, .speechStart):
            // User started/is speaking during barge-in
            state = .userSpeaking

        case (.bargeIn, .speechEnd):
            // User finished their interruption
            state = .endOfUtterance

        case (.bargeIn, .serverResponseDone):
            // Previous response cancelled, ready to listen
            state = .listening

        case (.bargeIn, .disconnected):
            state = .reconnecting

        case (.bargeIn, .tapEnd):
            state = .ended

        case (.bargeIn, .toggleMute):
            isMuted.toggle()
            if isMuted {
                state = .muted
            }

        // MARK: - Muted State Transitions

        case (.muted, .toggleMute):
            isMuted = false
            state = .ready

        case (.muted, .tapEnd):
            state = .ended

        case (.muted, .disconnected):
            state = .reconnecting

        // MARK: - Reconnecting State Transitions

        case (.reconnecting, .connected):
            state = .ready

        case (.reconnecting, .disconnected):
            state = .error("Connection lost")

        case (.reconnecting, .serverError(let message)):
            state = .error(message)

        case (.reconnecting, .tapEnd):
            state = .ended

        // MARK: - Error State Transitions

        case (.error, .tapStart):
            state = .requestingPermissions

        case (.error, .tapEnd):
            state = .ended

        // MARK: - Ended State Transitions

        case (.ended, .tapStart):
            state = .requestingPermissions

        // MARK: - Global Events (handled in any state)

        case (_, .toggleCaptions):
            captionsEnabled.toggle()

        case (_, .selectVoice(let voiceId)):
            selectedVoiceId = voiceId

        case (_, .audioInterruptedBegin):
            // System audio interruption (phone call, Siri, etc.)
            if state.isActive && state != .muted {
                state = .muted
            }

        case (_, .audioInterruptedEnd):
            // Resume from system interruption
            if case .muted = state, !isMuted {
                state = .ready
            }

        case (_, .quotaExceeded):
            state = .error("Voice quota exceeded")

        case (_, .sessionTimeout):
            state = .error("Session timed out")

        // MARK: - Default (no transition)

        default:
            // State remains unchanged for unhandled event combinations
            break
        }

        #if DEBUG
        if state != previousState {
            // Build the message first so the logger's autoclosure doesn't capture `self`
            let old = previousState
            let new = state
            let evt = event
            let msg = "[VoiceStateMachine] \(old) -> \(new) (event: \(evt))"
            Log.voice.debug("\(msg, privacy: .public)")
        }
        #endif

        return state
    }

    // MARK: - Convenience Methods

    /// Reset to initial state
    mutating func reset() {
        state = .idle
        isMuted = false
    }

    /// Check if a specific event would cause a state transition
    func wouldTransition(for event: Event) -> Bool {
        var copy = self
        let newState = copy.send(event)
        return newState != state
    }
}

// MARK: - State Extensions for OrbView Compatibility

extension VoiceStateMachine.State {
    /// Convenience for checking idle state
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    /// Convenience for checking error state
    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    /// Convenience for checking ended state
    var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }
}

// MARK: - Logging descriptions

extension VoiceStateMachine.State: CustomStringConvertible {
    var description: String {
        switch self {
        case .idle: return "idle"
        case .requestingPermissions: return "requestingPermissions"
        case .connecting: return "connecting"
        case .ready: return "ready"
        case .listening: return "listening"
        case .userSpeaking: return "userSpeaking"
        case .endOfUtterance: return "endOfUtterance"
        case .sending: return "sending"
        case .thinking: return "thinking"
        case .processing: return "processing"
        case .speaking: return "speaking"
        case .bargeIn: return "bargeIn"
        case .muted: return "muted"
        case .reconnecting: return "reconnecting"
        case .error(let message): return "error(\(message))"
        case .ended: return "ended"
        }
    }
}

extension VoiceStateMachine.Event: CustomStringConvertible {
    var description: String {
        switch self {
        // UI Events
        case .tapStart: return "tapStart"
        case .tapEnd: return "tapEnd"
        case .tapInterrupt: return "tapInterrupt"
        case .toggleMute: return "toggleMute"
        case .toggleCaptions: return "toggleCaptions"
        case .selectVoice(let id): return "selectVoice(\(id))"

        // Permission Events
        case .micPermissionGranted: return "micPermissionGranted"
        case .micPermissionDenied: return "micPermissionDenied"
        case .speechPermissionGranted: return "speechPermissionGranted"
        case .speechPermissionDenied: return "speechPermissionDenied"

        // VAD Events
        case .speechStart: return "speechStart"
        case .speechEnd: return "speechEnd"
        case .endOfUtteranceDetected: return "endOfUtteranceDetected"

        // Transport Events
        case .connected: return "connected"
        case .disconnected: return "disconnected"
        case .serverTranscriptDelta(let text): return "serverTranscriptDelta(\(text))"
        case .serverAudioChunk(let data): return "serverAudioChunk(\(data.count) bytes)"
        case .serverThinking: return "serverThinking"
        case .serverResponseStart: return "serverResponseStart"
        case .serverResponseDone: return "serverResponseDone"
        case .serverError(let message): return "serverError(\(message))"

        // Audio Events
        case .audioPlaybackStarted: return "audioPlaybackStarted"
        case .audioPlaybackFinished: return "audioPlaybackFinished"

        // System Events
        case .audioInterruptedBegin: return "audioInterruptedBegin"
        case .audioInterruptedEnd: return "audioInterruptedEnd"
        case .routeChanged: return "routeChanged"
        case .sessionTimeout: return "sessionTimeout"
        case .quotaExceeded: return "quotaExceeded"
        }
    }
}
