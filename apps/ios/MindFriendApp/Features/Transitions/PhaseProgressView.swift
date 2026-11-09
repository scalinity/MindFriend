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
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                // Phase header
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("Phase \(userPathway.currentPhase)")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                        .textCase(.uppercase)

                    Text(userPathway.currentPhaseName)
                        .font(.title)
                        .fontWeight(.bold)

                    if let phaseDescription = viewModel.phaseDetails?.description {
                        Text(phaseDescription)
                            .font(.body)
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.top, SupportTheme.Spacing.m)

                // Progress in current phase
                if let phaseDetails = viewModel.phaseDetails {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        HStack {
                            Text("Phase Progress")
                                .font(.headline)

                            Spacer()

                            Text("Day \(userPathway.currentPhaseDay) of \(phaseDetails.durationDays)")
                                .font(.subheadline)
                                .foregroundColor(SupportTheme.textSecondary)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                    .fill(SupportTheme.textSecondary.opacity(0.2))
                                    .frame(height: 12)

                                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                    .fill(SupportTheme.accent)
                                    .frame(width: geometry.size.width * phaseProgress, height: 12)
                            }
                        }
                        .frame(height: 12)
                    }
                    .supportCard()
                    .padding(.horizontal, SupportTheme.Spacing.m)
                }

                // Objectives
                if let objectives = viewModel.phaseDetails?.objectives, !objectives.isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Phase Objectives")
                            .font(.headline)

                        ForEach(Array(objectives.enumerated()), id: \.offset) { _, objective in
                            HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(SupportTheme.accent)
                                    .font(.system(.title3))
                                    .accessibilityHidden(true)

                                Text(objective)
                                    .font(.body)
                                    .foregroundColor(SupportTheme.textPrimary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Objective: \(objective)")
                        }
                    }
                    .supportCard()
                    .padding(.horizontal, SupportTheme.Spacing.m)
                }

                // Milestones
                if !viewModel.milestones.isEmpty {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Milestones Achieved")
                            .font(.headline)

                        ForEach(viewModel.milestones) { milestone in
                            HStack(spacing: SupportTheme.Spacing.s) {
                                Image(systemName: "star.fill")
                                    .foregroundColor(SupportTheme.accent)
                                    .font(.system(.title2))

                                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                                    Text(milestone.milestoneKey)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text(milestone.achievedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(SupportTheme.textSecondary)
                                }

                                Spacer()
                            }
                            .padding(.vertical, SupportTheme.Spacing.xs)
                        }
                    }
                    .supportCard()
                    .padding(.horizontal, SupportTheme.Spacing.m)
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
                                .font(.system(.title2))
                        }
                        .padding(SupportTheme.Spacing.m)
                        .frame(maxWidth: .infinity)
                        .background(SupportTheme.accent)
                        .foregroundColor(SupportTheme.onAccent)
                        .cornerRadius(SupportTheme.controlRadius)
                    }
                    .accessibilityLabel("Advance to next phase")
                    .accessibilityHint("You have completed the current phase. Double tap to begin the next phase of your journey.")
                    .padding(.horizontal, SupportTheme.Spacing.m)
                }
            }
            .padding(.bottom, SupportTheme.Spacing.l)
        }
        .background(SupportTheme.surface)
        .supportScreen()
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
        .safeAreaInset(edge: .bottom) {
                if viewModel.showError {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    Text(viewModel.errorMessage)

                    Button("OK") {
                        viewModel.showError = false
                    }
                }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
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
