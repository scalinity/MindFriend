import Foundation
import SwiftUI
import Combine

/// Coordinates voice service events with the voice state machine
/// Eliminates dual state management by providing a single event flow
@MainActor
final class VoiceCoordinator: ObservableObject, VoiceServiceDelegate {

    // Callbacks for view updates
    var onError: ((String) -> Void)?
    var onQuotaExceeded: (() -> Void)?
    var onTranscriptUpdate: ((String) -> Void)?
    var onAssistantSpeechStart: ((String) -> Void)?
    var onAssistantSpeechEnd: (() -> Void)?

    // Callback to send events to the state machine
    var onStateEvent: ((VoiceStateMachine.Event) -> Void)?

    init() {}

    // MARK: - VoiceServiceDelegate

    func voiceService(_ service: any VoiceServiceProtocol, didEmit event: VoiceServiceEvent) {
        switch event {
        case .connectionStateChanged(let state):
            handleConnectionStateChange(state)

        case .listeningStarted:
            // Listening state is managed by service, no state machine event needed
            break

        case .listeningEnded:
            // Listening state is managed by service, no state machine event needed
            break

        case .userSpeechStarted:
            onStateEvent?(.speechStart)

        case .userSpeechEnded:
            onStateEvent?(.speechEnd)
            onStateEvent?(.serverThinking)

        case .assistantSpeechStarted:
            // Capture baseline transcript for this speech segment
            let baselineTranscript = service.transcribedText
            onAssistantSpeechStart?(baselineTranscript)
            onStateEvent?(.serverAudioChunk(Data()))

        case .assistantSpeechEnded:
            onAssistantSpeechEnd?()
            onStateEvent?(.audioPlaybackFinished)

        case .bargeInTriggered:
            // Barge-in: user interrupted AI, transition to bargeIn state then userSpeaking
            onStateEvent?(.tapInterrupt)

        case .transcriptUpdated(let text):
            onTranscriptUpdate?(text)

        case .quotaUpdated:
            // Quota display is bound directly to service property
            break

        case .emotionDetected:
            // Emotion state is managed directly by service and view
            // No state machine event needed
            break

        case .error(let error):
            handleError(error)
        }
    }

    // MARK: - Private Helpers

    private func handleConnectionStateChange(_ state: VoiceConnectionState) {
        switch state {
        case .connected:
            onStateEvent?(.connected)

        case .connecting:
            // Transient state, no state machine event
            break

        case .reconnecting, .disconnected:
            onStateEvent?(.disconnected)

        case .error(let message):
            onStateEvent?(.serverError(message))
            onError?(message)

            // Check for quota-related errors
            if message.lowercased().contains("quota") {
                onQuotaExceeded?()
            }
        }
    }

    private func handleError(_ error: VoiceError) {
        onError?(error.localizedDescription)

        switch error {
        case .quotaExceeded:
            onStateEvent?(.quotaExceeded)
            onQuotaExceeded?()

        case .microphonePermissionDenied:
            onStateEvent?(.micPermissionDenied)

        default:
            onStateEvent?(.serverError(error.localizedDescription))
        }
    }
}
