import XCTest
@testable import MindFriendApp

final class VoiceStateMachineTests: XCTestCase {

    // MARK: - Initial State Tests

    func testInitialState() {
        let machine = VoiceStateMachine()
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(machine.isMuted)
        XCTAssertTrue(machine.captionsEnabled)
    }

    func testCustomInitialState() {
        let machine = VoiceStateMachine(
            initialState: .ready,
            isMuted: true,
            captionsEnabled: false,
            selectedVoiceId: "voice-1"
        )
        XCTAssertEqual(machine.state, .ready)
        XCTAssertTrue(machine.isMuted)
        XCTAssertFalse(machine.captionsEnabled)
        XCTAssertEqual(machine.selectedVoiceId, "voice-1")
    }

    // MARK: - Idle State Transitions

    func testIdleToRequestingPermissions() {
        var machine = VoiceStateMachine()
        let newState = machine.send(.tapStart)
        XCTAssertEqual(newState, .requestingPermissions)
    }

    func testIdleIgnoresOtherEvents() {
        var machine = VoiceStateMachine()
        _ = machine.send(.speechStart)
        XCTAssertEqual(machine.state, .idle)

        _ = machine.send(.connected)
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Permission State Transitions

    func testPermissionGrantedToConnecting() {
        var machine = VoiceStateMachine(initialState: .requestingPermissions)
        let newState = machine.send(.micPermissionGranted)
        XCTAssertEqual(newState, .connecting)
    }

    func testPermissionDeniedToError() {
        var machine = VoiceStateMachine(initialState: .requestingPermissions)
        let newState = machine.send(.micPermissionDenied)
        XCTAssertEqual(newState, .error("Microphone access required"))
    }

    // MARK: - Connecting State Transitions

    func testConnectingToReady() {
        var machine = VoiceStateMachine(initialState: .connecting)
        let newState = machine.send(.connected)
        XCTAssertEqual(newState, .ready)
    }

    func testConnectingToErrorOnDisconnect() {
        var machine = VoiceStateMachine(initialState: .connecting)
        let newState = machine.send(.disconnected)
        XCTAssertEqual(newState, .error("Connection failed"))
    }

    func testConnectingToErrorOnServerError() {
        var machine = VoiceStateMachine(initialState: .connecting)
        let newState = machine.send(.serverError("Network timeout"))
        XCTAssertEqual(newState, .error("Network timeout"))
    }

    // MARK: - Ready State Transitions

    func testReadyToUserSpeakingOnSpeechStart() {
        var machine = VoiceStateMachine(initialState: .ready)
        let newState = machine.send(.speechStart)
        XCTAssertEqual(newState, .userSpeaking)
    }

    func testReadyToEnded() {
        var machine = VoiceStateMachine(initialState: .ready)
        let newState = machine.send(.tapEnd)
        XCTAssertEqual(newState, .ended)
    }

    func testReadyToggleMuteToMuted() {
        var machine = VoiceStateMachine(initialState: .ready)
        let newState = machine.send(.toggleMute)
        XCTAssertEqual(newState, .muted)
        XCTAssertTrue(machine.isMuted)
    }

    func testReadyToReconnecting() {
        var machine = VoiceStateMachine(initialState: .ready)
        let newState = machine.send(.disconnected)
        XCTAssertEqual(newState, .reconnecting)
    }

    func testReadyIgnoresSpeechStartWhenMuted() {
        var machine = VoiceStateMachine(initialState: .ready, isMuted: true)
        let newState = machine.send(.speechStart)
        XCTAssertEqual(newState, .ready) // Should not transition when muted
    }

    // MARK: - User Speaking State Transitions

    func testUserSpeakingToEndOfUtterance() {
        var machine = VoiceStateMachine(initialState: .userSpeaking)
        let newState = machine.send(.speechEnd)
        XCTAssertEqual(newState, .endOfUtterance)
    }

    func testUserSpeakingToggleMuteToMuted() {
        var machine = VoiceStateMachine(initialState: .userSpeaking)
        let newState = machine.send(.toggleMute)
        XCTAssertEqual(newState, .muted)
        XCTAssertTrue(machine.isMuted)
    }

    func testUserSpeakingToEnded() {
        var machine = VoiceStateMachine(initialState: .userSpeaking)
        let newState = machine.send(.tapEnd)
        XCTAssertEqual(newState, .ended)
    }

    func testUserSpeakingToReconnecting() {
        var machine = VoiceStateMachine(initialState: .userSpeaking)
        let newState = machine.send(.disconnected)
        XCTAssertEqual(newState, .reconnecting)
    }

    // MARK: - End of Utterance State Transitions

    func testEndOfUtteranceToThinking() {
        var machine = VoiceStateMachine(initialState: .endOfUtterance)
        let newState = machine.send(.serverThinking)
        XCTAssertEqual(newState, .thinking)
    }

    func testEndOfUtteranceToThinkingOnResponseStart() {
        var machine = VoiceStateMachine(initialState: .endOfUtterance)
        let newState = machine.send(.serverResponseStart)
        XCTAssertEqual(newState, .thinking)
    }

    func testEndOfUtteranceToReconnecting() {
        var machine = VoiceStateMachine(initialState: .endOfUtterance)
        let newState = machine.send(.disconnected)
        XCTAssertEqual(newState, .reconnecting)
    }

    // MARK: - Thinking State Transitions

    func testThinkingToSpeakingOnAudioChunk() {
        var machine = VoiceStateMachine(initialState: .thinking)
        let newState = machine.send(.serverAudioChunk(Data()))
        XCTAssertEqual(newState, .speaking)
    }

    func testThinkingToReadyOnResponseDone() {
        var machine = VoiceStateMachine(initialState: .thinking)
        let newState = machine.send(.serverResponseDone)
        XCTAssertEqual(newState, .ready)
    }

    func testThinkingToBargeInOnSpeechStart() {
        var machine = VoiceStateMachine(initialState: .thinking)
        let newState = machine.send(.speechStart)
        XCTAssertEqual(newState, .bargeIn)
    }

    func testThinkingToBargeInOnTapInterrupt() {
        var machine = VoiceStateMachine(initialState: .thinking)
        let newState = machine.send(.tapInterrupt)
        XCTAssertEqual(newState, .bargeIn)
    }

    func testThinkingToReconnecting() {
        var machine = VoiceStateMachine(initialState: .thinking)
        let newState = machine.send(.disconnected)
        XCTAssertEqual(newState, .reconnecting)
    }

    func testThinkingToError() {
        var machine = VoiceStateMachine(initialState: .thinking)
        let newState = machine.send(.serverError("AI unavailable"))
        XCTAssertEqual(newState, .error("AI unavailable"))
    }

    // MARK: - Speaking State Transitions (Barge-In)

    func testSpeakingToBargeInOnSpeechStart() {
        var machine = VoiceStateMachine(initialState: .speaking)
        let newState = machine.send(.speechStart)
        XCTAssertEqual(newState, .bargeIn)
    }

    func testSpeakingToBargeInOnTapInterrupt() {
        var machine = VoiceStateMachine(initialState: .speaking)
        let newState = machine.send(.tapInterrupt)
        XCTAssertEqual(newState, .bargeIn)
    }

    func testSpeakingToReadyOnPlaybackFinished() {
        var machine = VoiceStateMachine(initialState: .speaking)
        let newState = machine.send(.audioPlaybackFinished)
        XCTAssertEqual(newState, .ready)
    }

    func testSpeakingStaysOnResponseDone() {
        // Speaking should wait for playback to finish
        var machine = VoiceStateMachine(initialState: .speaking)
        let newState = machine.send(.serverResponseDone)
        XCTAssertEqual(newState, .speaking)
    }

    func testSpeakingToReconnecting() {
        var machine = VoiceStateMachine(initialState: .speaking)
        let newState = machine.send(.disconnected)
        XCTAssertEqual(newState, .reconnecting)
    }

    func testSpeakingToggleMuteToMuted() {
        var machine = VoiceStateMachine(initialState: .speaking)
        let newState = machine.send(.toggleMute)
        XCTAssertEqual(newState, .muted)
        XCTAssertTrue(machine.isMuted)
    }

    // MARK: - Barge-In State Transitions

    func testBargeInToUserSpeakingOnPlaybackFinished() {
        var machine = VoiceStateMachine(initialState: .bargeIn)
        let newState = machine.send(.audioPlaybackFinished)
        XCTAssertEqual(newState, .userSpeaking)
    }

    func testBargeInToEndOfUtteranceOnSpeechEnd() {
        var machine = VoiceStateMachine(initialState: .bargeIn)
        let newState = machine.send(.speechEnd)
        XCTAssertEqual(newState, .endOfUtterance)
    }

    func testBargeInToReconnecting() {
        var machine = VoiceStateMachine(initialState: .bargeIn)
        let newState = machine.send(.disconnected)
        XCTAssertEqual(newState, .reconnecting)
    }

    func testBargeInToUserSpeakingOnSpeechStart() {
        var machine = VoiceStateMachine(initialState: .bargeIn)
        let newState = machine.send(.speechStart)
        XCTAssertEqual(newState, .userSpeaking)
    }

    // MARK: - Muted State Transitions

    func testMutedToReadyOnToggleMute() {
        var machine = VoiceStateMachine(initialState: .muted, isMuted: true)
        let newState = machine.send(.toggleMute)
        XCTAssertEqual(newState, .ready)
        XCTAssertFalse(machine.isMuted)
    }

    func testMutedToEnded() {
        var machine = VoiceStateMachine(initialState: .muted)
        let newState = machine.send(.tapEnd)
        XCTAssertEqual(newState, .ended)
    }

    func testMutedToReconnecting() {
        var machine = VoiceStateMachine(initialState: .muted)
        let newState = machine.send(.disconnected)
        XCTAssertEqual(newState, .reconnecting)
    }

    // MARK: - Reconnecting State Transitions

    func testReconnectingToReady() {
        var machine = VoiceStateMachine(initialState: .reconnecting)
        let newState = machine.send(.connected)
        XCTAssertEqual(newState, .ready)
    }

    func testReconnectingToErrorOnDisconnect() {
        var machine = VoiceStateMachine(initialState: .reconnecting)
        let newState = machine.send(.disconnected)
        XCTAssertEqual(newState, .error("Connection lost"))
    }

    func testReconnectingToErrorOnServerError() {
        var machine = VoiceStateMachine(initialState: .reconnecting)
        let newState = machine.send(.serverError("Server unavailable"))
        XCTAssertEqual(newState, .error("Server unavailable"))
    }

    func testReconnectingToEnded() {
        var machine = VoiceStateMachine(initialState: .reconnecting)
        let newState = machine.send(.tapEnd)
        XCTAssertEqual(newState, .ended)
    }

    // MARK: - Error State Transitions

    func testErrorToRequestingPermissionsOnTapStart() {
        var machine = VoiceStateMachine(initialState: .error("Previous error"))
        let newState = machine.send(.tapStart)
        XCTAssertEqual(newState, .requestingPermissions)
    }

    func testErrorToEnded() {
        var machine = VoiceStateMachine(initialState: .error("Previous error"))
        let newState = machine.send(.tapEnd)
        XCTAssertEqual(newState, .ended)
    }

    // MARK: - Ended State Transitions

    func testEndedToRequestingPermissionsOnTapStart() {
        var machine = VoiceStateMachine(initialState: .ended)
        let newState = machine.send(.tapStart)
        XCTAssertEqual(newState, .requestingPermissions)
    }

    // MARK: - Global Events

    func testToggleCaptionsFromAnyState() {
        var machine = VoiceStateMachine(captionsEnabled: true)
        _ = machine.send(.toggleCaptions)
        XCTAssertFalse(machine.captionsEnabled)

        _ = machine.send(.toggleCaptions)
        XCTAssertTrue(machine.captionsEnabled)
    }

    func testSelectVoiceFromAnyState() {
        var machine = VoiceStateMachine()
        XCTAssertNil(machine.selectedVoiceId)

        _ = machine.send(.selectVoice("voice-ara"))
        XCTAssertEqual(machine.selectedVoiceId, "voice-ara")

        _ = machine.send(.selectVoice("voice-rex"))
        XCTAssertEqual(machine.selectedVoiceId, "voice-rex")
    }

    func testAudioInterruptedBeginMutesActiveState() {
        var machine = VoiceStateMachine(initialState: .speaking)
        _ = machine.send(.audioInterruptedBegin)
        XCTAssertEqual(machine.state, .muted)
    }

    func testAudioInterruptedBeginIgnoresInactiveState() {
        var machine = VoiceStateMachine(initialState: .idle)
        _ = machine.send(.audioInterruptedBegin)
        XCTAssertEqual(machine.state, .idle)
    }

    func testAudioInterruptedEndResumesToReady() {
        var machine = VoiceStateMachine(initialState: .muted, isMuted: false)
        _ = machine.send(.audioInterruptedEnd)
        XCTAssertEqual(machine.state, .ready)
    }

    func testAudioInterruptedEndStaysMutedIfUserMuted() {
        var machine = VoiceStateMachine(initialState: .muted, isMuted: true)
        _ = machine.send(.audioInterruptedEnd)
        XCTAssertEqual(machine.state, .muted) // Stay muted because user chose to mute
    }

    func testQuotaExceededToError() {
        var machine = VoiceStateMachine(initialState: .speaking)
        let newState = machine.send(.quotaExceeded)
        XCTAssertEqual(newState, .error("Voice quota exceeded"))
    }

    func testSessionTimeoutToError() {
        var machine = VoiceStateMachine(initialState: .ready)
        let newState = machine.send(.sessionTimeout)
        XCTAssertEqual(newState, .error("Session timed out"))
    }

    // MARK: - State Computed Properties

    func testOrbColorMapping() {
        XCTAssertEqual(VoiceStateMachine.State.idle.orbColor, .inactive)
        XCTAssertEqual(VoiceStateMachine.State.ended.orbColor, .inactive)
        XCTAssertEqual(VoiceStateMachine.State.connecting.orbColor, .connecting)
        XCTAssertEqual(VoiceStateMachine.State.requestingPermissions.orbColor, .connecting)
        XCTAssertEqual(VoiceStateMachine.State.ready.orbColor, .ready)
        XCTAssertEqual(VoiceStateMachine.State.listening.orbColor, .ready)
        XCTAssertEqual(VoiceStateMachine.State.userSpeaking.orbColor, .userSpeaking)
        XCTAssertEqual(VoiceStateMachine.State.bargeIn.orbColor, .userSpeaking)
        XCTAssertEqual(VoiceStateMachine.State.thinking.orbColor, .thinking)
        XCTAssertEqual(VoiceStateMachine.State.processing.orbColor, .thinking)
        XCTAssertEqual(VoiceStateMachine.State.speaking.orbColor, .aiSpeaking)
        XCTAssertEqual(VoiceStateMachine.State.muted.orbColor, .muted)
        XCTAssertEqual(VoiceStateMachine.State.reconnecting.orbColor, .reconnecting)
        XCTAssertEqual(VoiceStateMachine.State.error("test").orbColor, .error)
    }

    func testOrbIconMapping() {
        XCTAssertEqual(VoiceStateMachine.State.idle.orbIcon, "mic.fill")
        XCTAssertEqual(VoiceStateMachine.State.requestingPermissions.orbIcon, "lock.fill")
        XCTAssertEqual(VoiceStateMachine.State.connecting.orbIcon, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(VoiceStateMachine.State.ready.orbIcon, "ear")
        XCTAssertEqual(VoiceStateMachine.State.listening.orbIcon, "ear.fill")
        XCTAssertEqual(VoiceStateMachine.State.userSpeaking.orbIcon, "waveform")
        XCTAssertEqual(VoiceStateMachine.State.thinking.orbIcon, "brain")
        XCTAssertEqual(VoiceStateMachine.State.speaking.orbIcon, "speaker.wave.2.fill")
        XCTAssertEqual(VoiceStateMachine.State.muted.orbIcon, "mic.slash.fill")
        XCTAssertEqual(VoiceStateMachine.State.error("test").orbIcon, "exclamationmark.triangle.fill")
        XCTAssertEqual(VoiceStateMachine.State.ended.orbIcon, "checkmark.circle.fill")
    }

    func testIsActiveProperty() {
        XCTAssertFalse(VoiceStateMachine.State.idle.isActive)
        XCTAssertFalse(VoiceStateMachine.State.ended.isActive)
        XCTAssertFalse(VoiceStateMachine.State.error("test").isActive)

        XCTAssertTrue(VoiceStateMachine.State.connecting.isActive)
        XCTAssertTrue(VoiceStateMachine.State.ready.isActive)
        XCTAssertTrue(VoiceStateMachine.State.speaking.isActive)
        XCTAssertTrue(VoiceStateMachine.State.thinking.isActive)
    }

    func testShouldCaptureAudioProperty() {
        XCTAssertTrue(VoiceStateMachine.State.ready.shouldCaptureAudio)
        XCTAssertTrue(VoiceStateMachine.State.listening.shouldCaptureAudio)
        XCTAssertTrue(VoiceStateMachine.State.userSpeaking.shouldCaptureAudio)
        XCTAssertTrue(VoiceStateMachine.State.bargeIn.shouldCaptureAudio)
        XCTAssertTrue(VoiceStateMachine.State.speaking.shouldCaptureAudio)

        XCTAssertFalse(VoiceStateMachine.State.idle.shouldCaptureAudio)
        XCTAssertFalse(VoiceStateMachine.State.connecting.shouldCaptureAudio)
        XCTAssertFalse(VoiceStateMachine.State.thinking.shouldCaptureAudio)
        XCTAssertFalse(VoiceStateMachine.State.muted.shouldCaptureAudio)
    }

    func testIsPlaybackStateProperty() {
        XCTAssertTrue(VoiceStateMachine.State.speaking.isPlaybackState)

        XCTAssertFalse(VoiceStateMachine.State.idle.isPlaybackState)
        XCTAssertFalse(VoiceStateMachine.State.thinking.isPlaybackState)
        XCTAssertFalse(VoiceStateMachine.State.ready.isPlaybackState)
    }

    func testStatusTextProperty() {
        XCTAssertEqual(VoiceStateMachine.State.idle.statusText, "Tap to start")
        XCTAssertEqual(VoiceStateMachine.State.connecting.statusText, "Connecting...")
        XCTAssertEqual(VoiceStateMachine.State.ready.statusText, "Ready to listen")
        XCTAssertEqual(VoiceStateMachine.State.listening.statusText, "Listening...")
        XCTAssertEqual(VoiceStateMachine.State.userSpeaking.statusText, "Listening...")
        XCTAssertEqual(VoiceStateMachine.State.thinking.statusText, "Thinking...")
        XCTAssertEqual(VoiceStateMachine.State.speaking.statusText, "Speaking...")
        XCTAssertEqual(VoiceStateMachine.State.muted.statusText, "Muted")
        XCTAssertEqual(VoiceStateMachine.State.error("Network error").statusText, "Error: Network error")
        XCTAssertEqual(VoiceStateMachine.State.ended.statusText, "Session ended")
    }

    func testAllowsBargeInProperty() {
        XCTAssertTrue(VoiceStateMachine.State.speaking.allowsBargeIn)
        XCTAssertTrue(VoiceStateMachine.State.thinking.allowsBargeIn)
        XCTAssertTrue(VoiceStateMachine.State.processing.allowsBargeIn)

        XCTAssertFalse(VoiceStateMachine.State.idle.allowsBargeIn)
        XCTAssertFalse(VoiceStateMachine.State.ready.allowsBargeIn)
        XCTAssertFalse(VoiceStateMachine.State.userSpeaking.allowsBargeIn)
    }

    // MARK: - State Extension Convenience Properties

    func testIsIdleProperty() {
        XCTAssertTrue(VoiceStateMachine.State.idle.isIdle)
        XCTAssertFalse(VoiceStateMachine.State.ready.isIdle)
        XCTAssertFalse(VoiceStateMachine.State.speaking.isIdle)
    }

    func testIsErrorProperty() {
        XCTAssertTrue(VoiceStateMachine.State.error("test").isError)
        XCTAssertFalse(VoiceStateMachine.State.idle.isError)
        XCTAssertFalse(VoiceStateMachine.State.ready.isError)
    }

    func testIsEndedProperty() {
        XCTAssertTrue(VoiceStateMachine.State.ended.isEnded)
        XCTAssertFalse(VoiceStateMachine.State.idle.isEnded)
        XCTAssertFalse(VoiceStateMachine.State.ready.isEnded)
    }

    // MARK: - Reset Functionality

    func testReset() {
        var machine = VoiceStateMachine(initialState: .speaking, isMuted: true)
        machine.reset()
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(machine.isMuted)
    }

    // MARK: - Would Transition Helper

    func testWouldTransition() {
        let machine = VoiceStateMachine(initialState: .ready)

        XCTAssertTrue(machine.wouldTransition(for: .speechStart))
        XCTAssertTrue(machine.wouldTransition(for: .tapEnd))
        XCTAssertTrue(machine.wouldTransition(for: .toggleMute))

        XCTAssertFalse(machine.wouldTransition(for: .serverAudioChunk(Data())))
        XCTAssertFalse(machine.wouldTransition(for: .audioPlaybackFinished))
    }

    // MARK: - Full Flow Integration Tests

    func testCompleteVoiceSessionFlow() {
        var machine = VoiceStateMachine()

        // Start session
        XCTAssertEqual(machine.send(.tapStart), .requestingPermissions)
        XCTAssertEqual(machine.send(.micPermissionGranted), .connecting)
        XCTAssertEqual(machine.send(.connected), .ready)

        // User speaks
        XCTAssertEqual(machine.send(.speechStart), .userSpeaking)
        XCTAssertEqual(machine.send(.speechEnd), .endOfUtterance)

        // AI responds
        XCTAssertEqual(machine.send(.serverThinking), .thinking)
        XCTAssertEqual(machine.send(.serverAudioChunk(Data())), .speaking)
        XCTAssertEqual(machine.send(.audioPlaybackFinished), .ready)

        // End session
        XCTAssertEqual(machine.send(.tapEnd), .ended)
    }

    func testBargeInFlow() {
        var machine = VoiceStateMachine(initialState: .speaking)

        // User interrupts AI
        XCTAssertEqual(machine.send(.speechStart), .bargeIn)

        // Playback stops
        XCTAssertEqual(machine.send(.audioPlaybackFinished), .userSpeaking)

        // User finishes speaking
        XCTAssertEqual(machine.send(.speechEnd), .endOfUtterance)
    }

    func testReconnectFlow() {
        var machine = VoiceStateMachine(initialState: .speaking)

        // Connection drops
        XCTAssertEqual(machine.send(.disconnected), .reconnecting)

        // Reconnects successfully
        XCTAssertEqual(machine.send(.connected), .ready)
    }

    func testMuteUnmuteFlow() {
        var machine = VoiceStateMachine(initialState: .ready)

        // Mute
        XCTAssertEqual(machine.send(.toggleMute), .muted)
        XCTAssertTrue(machine.isMuted)

        // Unmute
        XCTAssertEqual(machine.send(.toggleMute), .ready)
        XCTAssertFalse(machine.isMuted)
    }
}
