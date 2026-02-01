import Foundation
import Combine
import Supabase

// MARK: - Coping Kit View Model

@MainActor
final class CopingKitsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var availableKits: [CopingKit] = []
    @Published var activeProgress: [KitProgress] = []
    @Published var selectedKit: CopingKit?
    @Published var currentStepIndex: Int = 0
    @Published var isLoading = false
    @Published var isCompleting = false
    @Published var error: CopingKitError?
    @Published var showError = false
    @Published var completionResult: KitCompletionResult?
    @Published var showCompletion = false
    @Published var showPremiumUpgrade = false

    // MARK: - Private Properties

    private let service: CopingKitService
    private var currentProgressId: String?

    // MARK: - Computed Properties

    var currentStep: CopingKitStep? {
        guard let kit = selectedKit,
              currentStepIndex < kit.steps.count else {
            return nil
        }
        return kit.steps[currentStepIndex]
    }

    var progressPercentage: Double {
        guard let kit = selectedKit else { return 0 }
        guard kit.stepsCount > 0 else { return 0 }
        return Double(currentStepIndex) / Double(kit.stepsCount)
    }

    var isKitComplete: Bool {
        guard let kit = selectedKit else { return false }
        return currentStepIndex >= kit.stepsCount
    }

    var hasActiveSession: Bool {
        currentProgressId != nil
    }

    var stepsRemaining: Int {
        guard let kit = selectedKit else { return 0 }
        return max(0, kit.stepsCount - currentStepIndex)
    }

    // MARK: - Initialization

    init(service: CopingKitService) {
        self.service = service
    }

    // MARK: - Public Methods

    func loadKits() async {
        isLoading = true
        error = nil

        do {
            async let kitsTask = service.fetchKits()
            async let progressTask = service.fetchActiveProgress()

            let (kits, progress) = try await (kitsTask, progressTask)

            availableKits = kits
            activeProgress = progress
        } catch let copingError as CopingKitError {
            error = copingError
            showError = true
        } catch {
            self.error = .serverError(statusCode: 0)
            showError = true
        }

        isLoading = false
    }

    func selectKit(_ kit: CopingKit) {
        // Check if premium and handle upgrade
        if kit.isPremium {
            showPremiumUpgrade = true
            return
        }

        selectedKit = kit
        currentStepIndex = 0
    }

    func resumeKit(_ progress: KitProgress) async {
        // Find the kit in available kits or fetch fresh
        if let kit = availableKits.first(where: { $0.id == progress.kitId }) {
            selectedKit = kit
            currentStepIndex = progress.currentStepIndex
        } else {
            // Reload to get fresh data
            await loadKits()
            if let kit = availableKits.first(where: { $0.id == progress.kitId }) {
                selectedKit = kit
                currentStepIndex = progress.currentStepIndex
            }
        }

        // Set progress ID for tracking
        // Note: The progress ID would come from the API, stored in activeProgress
        currentProgressId = progress.kitId
    }

    func startKit() async {
        guard let kit = selectedKit else { return }

        do {
            let progressId = try await service.startKit(kitId: kit.id)
            currentProgressId = progressId
            currentStepIndex = 0
        } catch let copingError as CopingKitError {
            error = copingError
            showError = true
        } catch {
            self.error = .serverError(statusCode: 0)
            showError = true
        }
    }

    func nextStep(result: [String: String]? = nil) async {
        guard let kit = selectedKit,
              let progressId = currentProgressId else { return }

        isCompleting = true

        do {
            let stepResult = try await service.completeStep(
                progressId: progressId,
                stepIndex: currentStepIndex,
                result: result
            )

            if stepResult.isComplete {
                // Kit complete - trigger completion flow
                await completeKit()
            } else {
                currentStepIndex = stepResult.nextStepIndex
            }
        } catch let copingError as CopingKitError {
            error = copingError
            showError = true
        } catch {
            self.error = .serverError(statusCode: 0)
            showError = true
        }

        isCompleting = false
    }

    func completeKit(feedback: KitFeedbackRequest? = nil) async {
        guard let progressId = currentProgressId else { return }

        isCompleting = true

        do {
            let result = try await service.completeKit(
                progressId: progressId,
                feedback: feedback
            )

            completionResult = result
            showCompletion = true
            currentProgressId = nil

            // Refresh data after completion
            await loadKits()
        } catch let copingError as CopingKitError {
            error = copingError
            showError = true
        } catch {
            self.error = .serverError(statusCode: 0)
            showError = true
        }

        isCompleting = false
    }

    func cancelKit() async {
        guard let progressId = currentProgressId else { return }

        do {
            try await service.cancelKit(progressId: progressId)
        } catch {
            // Silently fail - the session will expire anyway
            print("Failed to cancel kit: \(error)")
        }

        currentProgressId = nil
        selectedKit = nil
        currentStepIndex = 0
    }

    func togglePin(_ kit: CopingKit) async {
        guard let currentState = kit.userState else { return }

        do {
            try await service.togglePin(kitId: kit.id, pinned: !currentState.pinned)

            // Update local state
            if let index = availableKits.firstIndex(where: { $0.id == kit.id }) {
                availableKits[index].userState = CopingKitUserState(
                    pinned: !currentState.pinned,
                    lastUsedAt: currentState.lastUsedAt,
                    totalUses: currentState.totalUses,
                    hasActiveProgress: currentState.hasActiveProgress
                )
            }
        } catch {
            self.error = .serverError(statusCode: 0)
            showError = true
        }
    }

    func dismissError() {
        showError = false
        error = nil
    }

    func dismissCompletion() {
        showCompletion = false
        completionResult = nil
        selectedKit = nil
        currentStepIndex = 0
    }

    func dismissPremiumUpgrade() {
        showPremiumUpgrade = false
    }

    func submitFeedback(kitId: String, helpful: Bool, comment: String?) async throws {
        try await service.submitFeedback(kitId: kitId, helpful: helpful, comment: comment)
    }

    // MARK: - Navigation

    func goBack() async {
        if hasActiveSession {
            // Optionally cancel the session
            await cancelKit()
        }
        selectedKit = nil
        currentStepIndex = 0
    }

    func goToStep(_ index: Int) {
        guard let kit = selectedKit,
              index >= 0,
              index < kit.stepsCount else { return }

        currentStepIndex = index
    }

    // MARK: - Sample Data (for previews)

    #if DEBUG
    static func preview() -> CopingKitsViewModel {
        let viewModel = CopingKitsViewModel(service: CopingKitService(supabase: SupabaseClient.mock))

        viewModel.availableKits = [
            CopingKit(
                id: "1",
                title: "5-4-3-2-1 Grounding",
                description: "A sensory grounding technique to help you feel present.",
                contextTag: .anxiety,
                steps: [
                    CopingKitStep(
                        type: .grounding,
                        exerciseType: nil,
                        prompt: "5 things you can SEE",
                        durationSeconds: 60,
                        durationCycles: nil,
                        breathingPattern: nil,
                        instructions: nil
                    ),
                    CopingKitStep(
                        type: .grounding,
                        exerciseType: nil,
                        prompt: "4 things you can TOUCH",
                        durationSeconds: 60,
                        durationCycles: nil,
                        breathingPattern: nil,
                        instructions: nil
                    ),
                ],
                estimatedMinutes: 8,
                isPremium: false,
                userState: CopingKitUserState(pinned: true, lastUsedAt: nil, totalUses: 3, hasActiveProgress: false)
            ),
            CopingKit(
                id: "2",
                title: "Box Breathing",
                description: "A simple breathing technique to calm your nervous system.",
                contextTag: .stress,
                steps: [
                    CopingKitStep(
                        type: .breathing,
                        exerciseType: nil,
                        prompt: "Inhale for 4 seconds, hold for 4, exhale for 4, hold for 4",
                        durationSeconds: 120,
                        durationCycles: 4,
                        breathingPattern: .boxBreathing,
                        instructions: "Repeat for 4 cycles"
                    ),
                ],
                estimatedMinutes: 5,
                isPremium: false,
                userState: nil
            ),
        ]

        viewModel.activeProgress = []

        return viewModel
    }
    #endif
}

// Note: SupabaseClient.mock is defined in SupabaseClient.swift
