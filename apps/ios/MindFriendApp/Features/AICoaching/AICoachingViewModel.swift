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

        // Convert emotion intensities to EmotionEntry array
        let emotionEntries = emotionIntensities.map { name, intensity in
            EmotionEntry(emotion: name, intensity: intensity.value)
        }

        let record = ThoughtRecord(
            id: UUID().uuidString,
            userId: "", // Will be replaced by backend
            enrollmentId: nil,
            programDayNumber: nil,
            situation: activatingEvent,
            activatingEvent: activatingEvent,
            automaticThought: automaticThoughts.filter { !$0.isEmpty }.joined(separator: "; "),
            emotions: emotionEntries,
            evidenceFor: evidenceForThoughts.isEmpty ? nil : evidenceForThoughts,
            evidenceAgainst: evidenceAgainstThoughts.isEmpty ? nil : evidenceAgainstThoughts,
            balancedThought: balancedThought.isEmpty ? nil : balancedThought,
            newEmotionIntensity: nil,
            cognitiveDistortions: identifiedDistortions,
            aiAnalysis: nil,
            aiAnalysisRequestedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        isSaving = false
        return record
    }

    func loadExistingRecord(_ record: ThoughtRecord) {
        activatingEvent = record.activatingEvent ?? record.situation
        automaticThoughts = [record.automaticThought]

        // Map emotions to intensity dictionary
        for entry in record.emotions {
            if let intensity = EmotionIntensity(value: entry.intensity) {
                emotionIntensities[entry.emotion] = intensity
            }
        }

        identifiedDistortions = record.cognitiveDistortions
        evidenceForThoughts = record.evidenceFor ?? ""
        evidenceAgainstThoughts = record.evidenceAgainst ?? ""
        balancedThought = record.balancedThought ?? ""
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
                id: UUID().uuidString,
                userId: UUID().uuidString,
                enrollmentId: nil,
                programDayNumber: nil,
                situation: "Received critical feedback on my project at work",
                activatingEvent: "Received critical feedback on my project at work",
                automaticThought: "I'm not good enough; Everyone thinks I'm incompetent",
                emotions: [EmotionEntry(emotion: "Anxious", intensity: 70)],
                evidenceFor: nil,
                evidenceAgainst: nil,
                balancedThought: "One piece of feedback doesn't define my overall competence",
                newEmotionIntensity: nil,
                cognitiveDistortions: [.allOrNothing, .mindReading],
                aiAnalysis: nil,
                aiAnalysisRequestedAt: nil,
                createdAt: Date().addingTimeInterval(-86400),
                updatedAt: Date()
            )
        ]
        return vm
    }
}
#endif
