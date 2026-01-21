//
//  BoundaryPracticeView.swift
//  MindFriendApp
//
//  Integration with Conversation Rehearsal Studio for boundary practice
//

import SwiftUI

struct BoundaryPracticeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: BoundaryPracticeViewModel

    let boundary: BoundaryListItem

    init(service: BoundaryPlannerService, boundary: BoundaryListItem) {
        self.boundary = boundary
        _viewModel = StateObject(wrappedValue: BoundaryPracticeViewModel(service: service, boundary: boundary))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Boundary Context
                    VStack(alignment: .leading, spacing: 12) {
                        Text("practice.context_header")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: boundary.boundaryType.icon)
                                    .foregroundStyle(boundary.boundaryType.colorScheme)

                                Text(boundary.boundaryType.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(boundary.statementText)
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)

                    // Practice Options
                    VStack(alignment: .leading, spacing: 16) {
                        Text("practice.options_header")
                            .font(.headline)
                            .padding(.horizontal)

                        // Guided Practice
                        PracticeOptionCard(
                            title: "practice.option_guided_title",
                            icon: "person.fill.questionmark",
                            description: "practice.option_guided_description",
                            isRecommended: viewModel.practiceCount < 3
                        ) {
                            viewModel.startGuidedPractice()
                        }
                        .padding(.horizontal)

                        // Free Practice
                        PracticeOptionCard(
                            title: "practice.option_free_title",
                            icon: "bubble.left.and.bubble.right.fill",
                            description: "practice.option_free_description",
                            isRecommended: false
                        ) {
                            viewModel.startFreePractice()
                        }
                        .padding(.horizontal)

                        // Role Play with AI
                        PracticeOptionCard(
                            title: "practice.option_roleplay_title",
                            icon: "theatermasks.fill",
                            description: "practice.option_roleplay_description",
                            isRecommended: viewModel.practiceCount >= 1
                        ) {
                            viewModel.startRolePlay()
                        }
                        .padding(.horizontal)
                    }

                    // Practice History
                    if viewModel.practiceCount > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("practice.history_header")
                                .font(.headline)
                                .padding(.horizontal)

                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)

                                Text("practice.history_count \(viewModel.practiceCount)")
                                    .font(.body)

                                Spacer()

                                if viewModel.practiceCount >= 3 {
                                    Text("practice.history_ready_badge")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.green.opacity(0.2))
                                        .foregroundStyle(.green)
                                        .cornerRadius(8)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                    }

                    // Tips Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("practice.tips_header")
                            .font(.headline)
                            .padding(.horizontal)

                        VStack(spacing: 8) {
                            TipCard(
                                icon: "lightbulb.fill",
                                text: "practice.tip_start_simple"
                            )

                            TipCard(
                                icon: "repeat",
                                text: "practice.tip_repetition"
                            )

                            TipCard(
                                icon: "figure.mind.and.body",
                                text: "practice.tip_body_language"
                            )

                            TipCard(
                                icon: "heart.fill",
                                text: "practice.tip_self_compassion"
                            )
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("practice.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $viewModel.showRehearsalStudio) {
                // Navigate to Conversation Rehearsal Studio with custom scenario
                Text("Conversation Rehearsal Studio")
                    .navigationTitle("Rehearsal Studio")
            }
        }
    }
}

// MARK: - Practice Option Card

struct PracticeOptionCard: View {
    let title: LocalizedStringKey
    let icon: String
    let description: LocalizedStringKey
    let isRecommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Color.accentColor)
                    .cornerRadius(12)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)

                        if isRecommended {
                            Text("practice.recommended_badge")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .foregroundStyle(.blue)
                                .cornerRadius(4)
                        }
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tip Card

struct TipCard: View {
    let icon: String
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.accentColor)
                .frame(width: 24, height: 24)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - View Model

@MainActor
final class BoundaryPracticeViewModel: ObservableObject {
    let service: BoundaryPlannerService
    let boundary: BoundaryListItem

    @Published var showRehearsalStudio = false
    @Published var selectedPracticeMode: PracticeMode?

    var practiceCount: Int {
        boundary.practiceCount
    }

    init(service: BoundaryPlannerService, boundary: BoundaryListItem) {
        self.service = service
        self.boundary = boundary
    }

    func startGuidedPractice() {
        selectedPracticeMode = .guided
        createCustomScenarioAndNavigate()
    }

    func startFreePractice() {
        selectedPracticeMode = .free
        createCustomScenarioAndNavigate()
    }

    func startRolePlay() {
        selectedPracticeMode = .rolePlay
        createCustomScenarioAndNavigate()
    }

    private func createCustomScenarioAndNavigate() {
        isLoading = true
        Task {
            do {
                let supabase = DependencyContainer.shared.supabaseClient
                guard let userId = supabase.auth.currentUser?.id.uuidString else {
                    throw BoundaryPlannerError.unauthorized
                }
                
                // Create custom scenario record in custom_scenarios table
                let scenarioData: [String: AnyCodable] = [
                    "user_id": .init(userId),
                    "scenario_type": .init("boundary_practice"),
                    "title": .init(boundary.statementText),
                    "description": .init("Practice: " + boundary.statementText),
                    "context": .init(boundary.expectedImpact ?? ""),
                    "difficulty_level": .init("medium"),
                    "source_feature": .init("boundary_planner"),
                    "source_id": .init(boundary.id.uuidString)
                ]
                
                let response = try await supabase
                    .from("custom_scenarios")
                    .insert(scenarioData)
                    .select()
                    .single()
                    .execute()
                
                if let data = response.data {
                    if let scenarioId = data["id"] as? String {
                        selectedScenarioId = scenarioId
                        showPracticeMode = true
                        // Practice count will be auto-incremented by trigger
                    }
                }
                
                isLoading = false
            } catch {
                self.error = error
                isLoading = false
            }
        }
    }
}

// MARK: - Supporting Types

enum PracticeMode {
    case guided
    case free
    case rolePlay
}

// MARK: - Previews

#Preview {
    BoundaryPracticeView(
        service: BoundaryPlannerService(supabase: .mock),
        boundary: BoundaryListItem(
            id: UUID(),
            boundaryType: .time,
            statementText: "I need to stop working at 6pm to have family time.",
            whyMatters: "Family time is important for my well-being.",
            stakeholder: "My manager",
            status: .ready,
            practiceCount: 2,
            createdAt: Date(),
            updatedAt: Date(),
            hasFollowUp: false
        )
    )
}
