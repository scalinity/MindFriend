import Foundation
import SwiftUI

// MARK: - Circle Habits View Model

@MainActor
final class CircleHabitsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var templates: [CircleTemplate] = []
    @Published var upcomingCheckins: [CircleTemplate] = []
    @Published var pendingNudges: [CircleNudge] = []
    @Published var currentStreak: StreakStatus = .empty
    @Published var streakHistory: [StreakDay] = []
    @Published var recaps: [CircleRecap] = []

    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var selectedTemplateForCheckin: CircleTemplate?

    // MARK: - Data Loading

    private var loadTask: Task<Void, Never>?

    func loadData(container: DependencyContainer) async {
        loadTask?.cancel()

        loadTask = Task { [weak self] in
            guard let self = self, !Task.isCancelled else { return }
            self.isLoading = true

            async let loadTemplates: () = self.loadTemplates(container: container)
            async let loadNudges: () = self.loadNudges(container: container)
            async let loadStreak: () = self.loadStreakStatus(container: container)

            _ = await (loadTemplates, loadNudges, loadStreak)

            if !Task.isCancelled {
                self.isLoading = false
            }
        }
    }

    // MARK: - Template Operations

    private func loadTemplates(container: DependencyContainer) async {
        do {
            let request = CircleHabitsRequest(operation: .getTemplates, circleId: nil, template: nil, settings: nil, checkin: nil)
            let response: CircleHabitsResponse = try await container.supabaseDataService.invokeCircleHabitsFunction(request)

            if response.success, let data = response.data, let templates = data.templates {
                self.templates = templates
                self.upcomingCheckins = templates.filter { $0.isActive }
            }
        } catch {
            // Silently fail
        }
    }

    func createTemplate(_ template: CircleTemplate, container: DependencyContainer) async {
        do {
            let request = CircleHabitsRequest(
                operation: .createTemplate,
                circleId: template.circleId,
                template: template,
                settings: nil,
                checkin: nil
            )
            let response: CircleHabitsResponse = try await container.supabaseDataService.invokeCircleHabitsFunction(request)

            if response.success, let data = response.data, let newTemplate = data.templates?.first {
                templates.append(newTemplate)
            } else if let error = response.error {
                errorMessage = error.message
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Check-in Operations

    func startCheckin(_ template: CircleTemplate, container: DependencyContainer) async {
        selectedTemplateForCheckin = template
    }

    func submitCheckin(_ checkin: CircleCheckin, container: DependencyContainer) async {
        do {
            let request = CircleHabitsRequest(
                operation: .submitCheckin,
                circleId: checkin.circleId,
                template: nil,
                settings: nil,
                checkin: checkin
            )
            let response: CircleHabitsResponse = try await container.supabaseDataService.invokeCircleHabitsFunction(request)

            if response.success {
                await loadStreakStatus(container: container)
            } else if let error = response.error {
                errorMessage = error.message
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    // MARK: - Nudge Operations

    private func loadNudges(container: DependencyContainer) async {
        do {
            let request = CircleHabitsRequest(operation: .getNudges, circleId: nil, template: nil, settings: nil, checkin: nil)
            let response: CircleHabitsResponse = try await container.supabaseDataService.invokeCircleHabitsFunction(request)

            if response.success, let data = response.data, let nudges = data.nudges {
                self.pendingNudges = nudges.filter { $0.acknowledgedAt == nil }
            }
        } catch {
            // Silently fail
        }
    }

    func dismissNudge(_ nudge: CircleNudge, container: DependencyContainer) async {
        do {
            let request = CircleHabitsRequest(operation: .dismissNudge, circleId: nil, template: nil, settings: nil, checkin: nil)
            let _: CircleHabitsResponse = try await container.supabaseDataService.invokeCircleHabitsFunction(request)

            // Remove from local list
            pendingNudges.removeAll { $0.id == nudge.id }
        } catch {
            // Silently fail
        }
    }

    // MARK: - Streak Operations

    private func loadStreakStatus(container: DependencyContainer) async {
        do {
            let request = CircleHabitsRequest(operation: .getStreakStatus, circleId: nil, template: nil, settings: nil, checkin: nil)
            let response: CircleHabitsResponse = try await container.supabaseDataService.invokeCircleHabitsFunction(request)

            if response.success, let data = response.data, let streak = data.streakStatus {
                currentStreak = streak
                streakHistory = generateStreakHistory()
            }
        } catch {
            // Silently fail
        }
    }

    private func generateStreakHistory() -> [StreakDay] {
        var history: [StreakDay] = []
        let calendar = Calendar.current

        // Calculate the date when the streak started
        let streakStartDate: Date?
        if currentStreak.currentStreak > 0 {
            streakStartDate = calendar.date(byAdding: .day, value: -(currentStreak.currentStreak - 1), to: Date())
        } else {
            streakStartDate = nil
        }

        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let completed: Bool
                if let startDate = streakStartDate {
                    completed = date >= startDate
                } else {
                    completed = false
                }
                history.append(StreakDay(date: date, completed: completed))
            }
        }

        return history
    }

    // MARK: - Recap Operations

    func loadRecap(for circleId: UUID, container: DependencyContainer) async {
        do {
            let request = CircleHabitsRequest(
                operation: .getRecap,
                circleId: circleId,
                template: nil,
                settings: nil,
                checkin: nil
            )
            let response: CircleHabitsResponse = try await container.supabaseDataService.invokeCircleHabitsFunction(request)

            if response.success, let data = response.data, let recap = data.recap {
                if !recaps.contains(where: { $0.id == recap.id }) {
                    recaps.append(recap)
                }
            }
        } catch {
            // Silently fail
        }
    }
}

// MARK: - Supporting Types

struct StreakDay: Identifiable {
    let id = UUID()
    let date: Date
    let completed: Bool
}

// MARK: - Template Editor View Model

@MainActor
final class CircleTemplateEditorViewModel: ObservableObject {
    @Published var name = ""
    @Published var description = ""
    @Published var questions: [TemplateQuestionInput] = []
    @Published var reminderDays: Set<Int> = [1, 3, 5] // Mon, Wed, Fri
    @Published var reminderTime = "09:00"
    @Published var isActive = true

    var isValid: Bool {
        !name.isEmpty && !questions.isEmpty
    }

    func addQuestion(_ type: QuestionPromptType) {
        let question = TemplateQuestionInput(
            questionText: defaultQuestion(for: type),
            promptType: type,
            order: questions.count,
            isRequired: true
        )
        questions.append(question)
    }

    func removeQuestion(at index: Int) {
        questions.remove(at: index)
        // Reorder remaining questions
        for i in 0..<questions.count {
            questions[i].order = i
        }
    }

    private func defaultQuestion(for type: QuestionPromptType) -> String {
        switch type {
        case .mood: return "How are you feeling today?"
        case .gratitude: return "What are you grateful for?"
        case .intention: return "What's your intention for today?"
        case .reflection: return "What's on your mind?"
        case .numeric: return "Rate this aspect from 1-10"
        case .freeform: return "Share your thoughts..."
        }
    }
}

struct TemplateQuestionInput: Identifiable {
    let id = UUID()
    var questionText: String
    var promptType: QuestionPromptType
    var order: Int
    var isRequired: Bool
}

// MARK: - Preview Helpers

#if DEBUG
extension CircleHabitsViewModel {
    static var preview: CircleHabitsViewModel {
        let vm = CircleHabitsViewModel()
        vm.templates = [
            CircleTemplate(
                id: UUID(),
                circleId: UUID(),
                name: "Daily Check-in",
                description: "Quick daily mood and gratitude check",
                questions: [
                    TemplateQuestion(id: UUID(), questionText: "How are you feeling?", promptType: .mood, order: 0, isRequired: true),
                    TemplateQuestion(id: UUID(), questionText: "What are you grateful for?", promptType: .gratitude, order: 1, isRequired: true)
                ],
                reminderDays: [1, 2, 3, 4, 5],
                reminderTime: "09:00",
                isActive: true,
                createdAt: Date()
            )
        ]
        vm.upcomingCheckins = vm.templates
        vm.currentStreak = StreakStatus(currentStreak: 7, longestStreak: 14, lastCheckinDate: Date(), isAtRisk: false)
        vm.streakHistory = (0..<7).map {
            StreakDay(date: Calendar.current.date(byAdding: .day, value: -$0, to: Date())!, completed: $0 < 7)
        }
        return vm
    }
}
#endif
