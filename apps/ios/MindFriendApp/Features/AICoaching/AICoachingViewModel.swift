import Foundation
import SwiftUI

// MARK: - AI Coaching View Model

@MainActor
final class AICoachingViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var currentMode: ConversationMode?
    @Published var isSessionActive = false
    @Published var sessionStartedAt: Date?

    @Published var thoughtRecords: [ThoughtRecord] = []
    @Published var recentThoughtRecords: [ThoughtRecord] = []
    @Published var suggestedQuests: [AISuggestedQuest] = []

    @Published var preferences: CoachingModePreferences = .default

    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    // MARK: - Public Methods

    private var loadTask: Task<Void, Never>?

    func loadData(container: DependencyContainer) async {
        loadTask?.cancel()

        loadTask = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            self.isLoading = true

            async let loadMode: () = self.loadCurrentMode(container: container)
            async let loadRecords: () = self.loadThoughtRecords(container: container)
            async let loadQuests: () = self.loadSuggestedQuests(container: container)
            async let loadPreferences: () = self.loadPreferences(container: container)

            _ = await (loadMode, loadRecords, loadQuests, loadPreferences)

            if !Task.isCancelled {
                self.isLoading = false
            }
        }
    }

    func selectMode(_ mode: ConversationMode, container: DependencyContainer) async {
        do {
            let request = CoachingModeRequest(operation: .startSession, mode: mode)
            let response: CoachingModeResponse = try await container.supabaseDataService.invokeCoachingFunction(request)

            if response.success, let data = response.data {
                currentMode = data.currentMode
                isSessionActive = data.sessionActive ?? false
                sessionStartedAt = data.sessionStartedAt
            } else if let error = response.error {
                errorMessage = error.message
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func endSession(container: DependencyContainer) async {
        do {
            let request = CoachingModeRequest(operation: .endSession)
            let response: CoachingModeResponse = try await container.supabaseDataService.invokeCoachingFunction(request)

            if response.success {
                currentMode = nil
                isSessionActive = false
                sessionStartedAt = nil
            } else if let error = response.error {
                errorMessage = error.message
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Private Methods

    private func loadCurrentMode(container: DependencyContainer) async {
        do {
            let request = CoachingModeRequest(operation: .getState)
            let response: CoachingModeResponse = try await container.supabaseDataService.invokeCoachingFunction(request)

            if response.success, let data = response.data {
                currentMode = data.currentMode
                isSessionActive = data.sessionActive ?? false
                sessionStartedAt = data.sessionStartedAt
            }
        } catch {
            // Silently fail - mode might not be set
        }
    }

    private func loadThoughtRecords(container: DependencyContainer) async {
        do {
            let request = CoachingModeRequest(operation: .getThoughtRecords)
            let response: CoachingModeResponse = try await container.supabaseDataService.invokeCoachingFunction(request)

            if response.success, let data = response.data, let records = data.thoughtRecords {
                thoughtRecords = records
                recentThoughtRecords = records.sorted { $0.createdAt > $1.createdAt }
            }
        } catch {
            // Silently fail
        }
    }

    private func loadSuggestedQuests(container: DependencyContainer) async {
        do {
            let request = CoachingModeRequest(operation: .getSuggestedQuests)
            let response: CoachingModeResponse = try await container.supabaseDataService.invokeCoachingFunction(request)

            if response.success, let data = response.data, let quests = data.suggestedQuests {
                suggestedQuests = quests.filter { $0.isAccepted == nil }
            }
        } catch {
            // Silently fail
        }
    }

    private func loadPreferences(container: DependencyContainer) async {
        do {
            let request = CoachingModeRequest(operation: .getState)
            let response: CoachingModeResponse = try await container.supabaseDataService.invokeCoachingFunction(request)

            if response.success, let data = response.data, let prefs = data.preferences {
                preferences = prefs
            }
        } catch {
            // Silently fail - use defaults
        }
    }
}

// MARK: - AI Coaching Thought Record View Model

@MainActor
final class AICoachingThoughtRecordViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var activatingEvent = ""
    @Published var automaticThoughts: [String] = [""]
    @Published var emotionIntensities: [String: EmotionIntensity] = [:]
    @Published var identifiedDistortions: [CognitiveDistortion] = []
    @Published var evidenceForThoughts = ""
    @Published var evidenceAgainstThoughts = ""
    @Published var balancedThought = ""
    @Published var alternativePerspective = ""
    @Published var outcomeEmotions: [String] = []
    @Published var lessonLearned = ""

    @Published var aiSuggestion: String?

    @Published var isSaving = false
    @Published var showError = false
    @Published var errorMessage = ""

    // MARK: - Computed Properties

    var hasChanges: Bool {
        !activatingEvent.isEmpty ||
        automaticThoughts.contains { !$0.isEmpty } ||
        !emotionIntensities.isEmpty ||
        !identifiedDistortions.isEmpty
    }

    // MARK: - Public Methods

    func createThoughtRecord() async -> ThoughtRecord? {
        isSaving = true

        // Extract emotion intensities from dictionary values
        let emotions = Array(emotionIntensities.values)

        let record = ThoughtRecord(
            id: UUID(),
            userId: UUID(), // Will be replaced by backend
            conversationId: nil,
            createdAt: Date(),
            updatedAt: Date(),
            activatingEvent: activatingEvent,
            automaticThoughts: automaticThoughts.filter { !$0.isEmpty },
            emotions: emotions,
            physicalSensations: nil,
            behaviors: nil,
            identifiedDistortions: identifiedDistortions,
            evidenceForThoughts: evidenceForThoughts.isEmpty ? nil : evidenceForThoughts,
            evidenceAgainstThoughts: evidenceAgainstThoughts.isEmpty ? nil : evidenceAgainstThoughts,
            balancedThought: balancedThought.isEmpty ? nil : balancedThought,
            alternativePerspective: alternativePerspective.isEmpty ? nil : alternativePerspective,
            emotionAfterReframing: outcomeEmotions.isEmpty ? nil : outcomeEmotions.map { _ in EmotionIntensity.low },
            lessonLearned: lessonLearned.isEmpty ? nil : lessonLearned,
            isCompleted: !balancedThought.isEmpty
        )

        isSaving = false
        return record
    }

    func loadExistingRecord(_ record: ThoughtRecord) {
        activatingEvent = record.activatingEvent
        automaticThoughts = record.automaticThoughts.isEmpty ? [""] : record.automaticThoughts

        // This would need mapping from the record's emotions
        identifiedDistortions = record.identifiedDistortions
        evidenceForThoughts = record.evidenceForThoughts ?? ""
        evidenceAgainstThoughts = record.evidenceAgainstThoughts ?? ""
        balancedThought = record.balancedThought ?? ""
        alternativePerspective = record.alternativePerspective ?? ""
        lessonLearned = record.lessonLearned ?? ""
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension AICoachingViewModel {
    static var preview: AICoachingViewModel {
        let vm = AICoachingViewModel()
        vm.currentMode = .reflect
        vm.isSessionActive = true
        vm.recentThoughtRecords = [
            ThoughtRecord(
                id: UUID(),
                userId: UUID(),
                conversationId: nil,
                createdAt: Date().addingTimeInterval(-86400),
                updatedAt: Date(),
                activatingEvent: "Received critical feedback on my project at work",
                automaticThoughts: ["I'm not good enough", "Everyone thinks I'm incompetent"],
                emotions: [.medium],
                physicalSensations: nil,
                behaviors: nil,
                identifiedDistortions: [.allOrNothing, .mindReading],
                evidenceForThoughts: nil,
                evidenceAgainstThoughts: nil,
                balancedThought: "One piece of feedback doesn't define my overall competence",
                alternativePerspective: nil,
                emotionAfterReframing: nil,
                lessonLearned: nil,
                isCompleted: true
            )
        ]
        return vm
    }
}
#endif
