//
//  PhaseProgressView.swift
//  MindFriendApp
//
//  Created by Claude on 2026-01-25.
//

import SwiftUI

struct PhaseProgressView: View {
    let userPathway: UserPathway
    @StateObject private var viewModel: PhaseProgressViewModel

    init(userPathway: UserPathway, transitionService: TransitionService) {
        self.userPathway = userPathway
        _viewModel = StateObject(wrappedValue: PhaseProgressViewModel(
            userPathway: userPathway,
            transitionService: transitionService
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Phase header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Phase \(userPathway.currentPhase)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    Text(userPathway.currentPhaseName)
                        .font(.title)
                        .fontWeight(.bold)

                    if let phaseDescription = viewModel.phaseDetails?.description {
                        Text(phaseDescription)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.top)

                // Progress in current phase
                if let phaseDetails = viewModel.phaseDetails {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Phase Progress")
                                .font(.headline)

                            Spacer()

                            Text("Day \(userPathway.currentPhaseDay) of \(phaseDetails.durationDays)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(height: 12)

                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.blue)
                                    .frame(width: geometry.size.width * phaseProgress, height: 12)
                            }
                        }
                        .frame(height: 12)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)
                }

                // Objectives
                if let objectives = viewModel.phaseDetails?.objectives, !objectives.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Phase Objectives")
                            .font(.headline)

                        ForEach(Array(objectives.enumerated()), id: \.offset) { _, objective in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 20))
                                    .accessibilityHidden(true)

                                Text(objective)
                                    .font(.body)
                                    .foregroundColor(.primary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Objective: \(objective)")
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)
                }

                // Milestones
                if !viewModel.milestones.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Milestones Achieved")
                            .font(.headline)

                        ForEach(viewModel.milestones) { milestone in
                            HStack(spacing: 12) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                    .font(.system(size: 24))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(milestone.milestoneKey)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text(milestone.achievedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .padding(.horizontal)
                }

                // Advance phase button
                if canAdvanceToNextPhase && userPathway.currentPhase < 4 {
                    Button {
                        viewModel.showAdvanceConfirmation = true
                    } label: {
                        HStack {
                            Text("Advance to Next Phase")
                                .font(.headline)

                            Spacer()

                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 24))
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Advance to next phase")
                    .accessibilityHint("You have completed the current phase. Double tap to begin the next phase of your journey.")
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Phase Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadPhaseDetails()
        }
        .confirmationDialog(
            "Ready to advance?",
            isPresented: $viewModel.showAdvanceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Yes, I'm ready") {
                Task {
                    await viewModel.advancePhase()
                }
            }
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("You've completed this phase. Are you ready to move to the next stage of your journey?")
        }
        .alert("Phase Advanced!", isPresented: $viewModel.showAdvanceSuccess) {
            Button("Continue") {
                viewModel.showAdvanceSuccess = false
            }
        } message: {
            Text("Welcome to \(viewModel.newPhaseName). Your journey continues.")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") {
                viewModel.showError = false
            }
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var phaseProgress: Double {
        guard let phaseDetails = viewModel.phaseDetails else { return 0 }
        return Double(userPathway.currentPhaseDay) / Double(phaseDetails.durationDays)
    }

    private var canAdvanceToNextPhase: Bool {
        guard let phaseDetails = viewModel.phaseDetails else { return false }
        return userPathway.currentPhaseDay >= phaseDetails.durationDays
    }
}

@MainActor
class PhaseProgressViewModel: ObservableObject {
    @Published var phaseDetails: PathwayPhase?
    @Published var milestones: [PathwayMilestone] = []
    @Published var showAdvanceConfirmation = false
    @Published var showAdvanceSuccess = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var newPhaseName = ""

    private let userPathway: UserPathway
    private let transitionService: TransitionService

    init(userPathway: UserPathway, transitionService: TransitionService) {
        self.userPathway = userPathway
        self.transitionService = transitionService
    }

    func loadPhaseDetails() async {
        // Fetch phase details from database
        guard let pathwayId = userPathway.pathway?.id else { return }
        
        do {
            // Fetch phase details
            self.phaseDetails = try await transitionService.fetchPhaseDetails(
                pathwayId: pathwayId,
                phaseNumber: userPathway.currentPhase
            )
            
            // Fetch milestones
            self.milestones = try await transitionService.fetchPhaseMilestones(
                userPathwayId: userPathway.id,
                phaseNumber: userPathway.currentPhase
            )
        } catch {
            print("Error loading phase details: \(error.localizedDescription)")
        }
    }

    func advancePhase() async {
        do {
            let response = try await transitionService.advancePhase(userPathwayId: userPathway.id)
            newPhaseName = response.phaseName
            showAdvanceSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    NavigationView {
        PhaseProgressView(
            userPathway: UserPathway(
                id: UUID(),
                userId: UUID(),
                pathwayId: UUID(),
                startedAt: Date(),
                currentPhase: 2,
                currentDay: 20,
                currentPhaseDay: 6,
                status: .active,
                pausedAt: nil,
                completedAt: nil,
                personalization: PathwayPersonalization(),
                createdAt: Date(),
                updatedAt: Date(),
                pathway: TransitionPathway(
                    id: UUID(),
                    key: "job_loss",
                    name: "Career Transition",
                    description: "Navigate job loss",
                    category: .career,
                    durationWeeks: 8,
                    phases: [
                        PathwayPhaseOverview(number: 1, name: "Acknowledge", focus: "Processing the change"),
                        PathwayPhaseOverview(number: 2, name: "Stabilize", focus: "Creating routine"),
                        PathwayPhaseOverview(number: 3, name: "Reflect", focus: "Understanding what you want"),
                        PathwayPhaseOverview(number: 4, name: "Rebuild", focus: "Taking action")
                    ],
                    isPremium: true,
                    iconName: "briefcase.fill",
                    color: "#5C6BC0",
                    crisisResources: nil,
                    createdAt: Date()
                ),
                progress: nil
            ),
            transitionService: DependencyContainer.shared.transitionService
        )
    }
}
