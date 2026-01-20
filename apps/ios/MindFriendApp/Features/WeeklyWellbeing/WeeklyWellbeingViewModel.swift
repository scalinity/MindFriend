import Foundation
import SwiftUI

// MARK: - Weekly Wellbeing View Model

@MainActor
final class WeeklyWellbeingViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var metrics: [WellbeingMetric] = []
    @Published var scores: [WellbeingCategory: Int] = [:]
    @Published var highlight = ""
    @Published var challenge = ""
    @Published var gratitude = ""

    @Published var history: [WeeklyWellbeingCheck] = []
    @Published var completedCheck: WeeklyWellbeingCheck?

    @Published var isLoading = false
    @Published var isSubmitting = false
    @Published var showError = false
    @Published var errorMessage = ""

    // MARK: - Initialization

    init() {
        initializeMetrics()
    }

    // MARK: - Public Methods

    func loadPreviousCheck(container: DependencyContainer) async {
        isLoading = true

        // Load previous check for comparison
        // This would call the wellbeing check edge function

        isLoading = false
    }

    func submitCheck(container: DependencyContainer) async {
        guard validateSubmission() else {
            return
        }

        isSubmitting = true

        do {
            let metricsInput = scores.map { category, score in
                WeeklyWellbeingRequest.WellbeingMetricInput(category: category, score: score)
            }

            let request = WeeklyWellbeingRequest(
                metrics: metricsInput,
                highlight: highlight.isEmpty ? nil : highlight,
                challenge: challenge.isEmpty ? nil : challenge,
                gratitude: gratitude.isEmpty ? nil : gratitude
            )

            // Call the weekly wellbeing edge function
            let response: WeeklyWellbeingResponse = try await container.supabaseDataService.submitWeeklyWellbeing(request)

            if response.success, let data = response.data {
                completedCheck = data.check
                history.insert(data.check, at: 0)
                resetScores()
            } else if let error = response.error {
                errorMessage = error.message
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isSubmitting = false
    }

    // MARK: - Private Methods

    private func initializeMetrics() {
        metrics = WellbeingCategory.allCases.map { category in
            WellbeingMetric(
                category: category,
                score: 5,
                previousScore: nil,
                trend: .stable
            )
        }
    }

    private func validateSubmission() -> Bool {
        // Check all required metrics have scores
        for category in WellbeingCategory.allCases {
            if scores[category] == nil {
                errorMessage = "Please rate all categories before submitting"
                showError = true
                return false
            }
        }
        return true
    }

    private func resetScores() {
        scores = [:]
        highlight = ""
        challenge = ""
        gratitude = ""
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension WeeklyWellbeingViewModel {
    static var preview: WeeklyWellbeingViewModel {
        let vm = WeeklyWellbeingViewModel()
        vm.scores = [
            .mood: 7,
            .energy: 6,
            .stress: 5,
            .sleep: 8,
            .social: 5,
            .purpose: 6
        ]
        vm.completedCheck = WeeklyWellbeingCheck(
            id: UUID(),
            userId: UUID(),
            weekStartDate: Date(),
            createdAt: Date(),
            overallMood: 7,
            energyLevel: 6,
            stressLevel: 5,
            sleepQuality: 8,
            socialConnection: 5,
            senseOfPurpose: 6,
            highlightOfWeek: "Finished a big project",
            challengeOfWeek: "Busy schedule",
            gratitudeNote: "Good weather",
            totalScore: 37,
            previousWeekScore: 35,
            trend: .improving
        )
        return vm
    }
}
#endif
