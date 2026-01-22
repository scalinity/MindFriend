import Foundation
import SwiftUI
import OSLog

@MainActor
class CoachViewModel: ObservableObject {
    @Published var suppressedUntil: Date?
    @Published var isAcknowledged = false
    @Published var interactionError: String?

    private let coachService: CoachServiceProtocol

    init(coachService: CoachServiceProtocol) {
        self.coachService = coachService
    }

    // MARK: - Suppression

    func isSuppressed() -> Bool {
        guard let suppressedUntil = suppressedUntil else { return false }
        return Date() < suppressedUntil
    }

    func suppressFor(minutes: Int) {
        suppressedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    // MARK: - Actions

    func handleAction(_ action: CoachInteraction.Action, encounterId: UUID?, distortionCode: String, confidence: Double) {
        Task {
            do {
                try await coachService.recordInteraction(
                    encounterId: encounterId,
                    distortionCode: distortionCode,
                    action: action,
                    confidence: confidence
                )

                // Handle side effects (no need for MainActor.run - already MainActor)
                switch action {
                case .helpful:
                    isAcknowledged = true

                case .dismissed:
                    suppressFor(minutes: 30)
                    isAcknowledged = true

                case .learnMore:
                    // Navigation handled by view
                    break

                case .shown:
                    // No action needed
                    break
                }
            } catch {
                // Use structured logging instead of print
                Logger(subsystem: "com.mindfriend.coach", category: "interaction").error("Failed to record coach interaction: \(error.localizedDescription)")
                interactionError = error.localizedDescription
            }
        }
    }
}
