import Foundation
import SwiftUI

@MainActor
class CoachViewModel: ObservableObject {
    @Published var suppressedUntil: Date?
    @Published var isAcknowledged = false

    private let coachService: CoachService

    init(coachService: CoachService) {
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

                // Handle side effects
                switch action {
                case .helpful:
                    await MainActor.run {
                        isAcknowledged = true
                    }

                case .dismissed:
                    await MainActor.run {
                        suppressFor(minutes: 30)
                        isAcknowledged = true
                    }

                case .learnMore:
                    // Navigation handled by view
                    break

                case .shown:
                    // No action needed
                    break
                }
            } catch {
                print("Failed to record coach interaction: \(error)")
            }
        }
    }
}
