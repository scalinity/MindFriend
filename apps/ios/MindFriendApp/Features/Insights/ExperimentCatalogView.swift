// ExperimentCatalogView.swift
// Displays curated list of available experiments

import SwiftUI

struct ExperimentCatalogView: View {
    @EnvironmentObject private var insightLabService: InsightLabService
    @State private var selectedExperiment: ExperimentActionType?
    @State private var isStarting = false
    @State private var startError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                // Header
                headerSection

                // Active experiment banner (if exists)
                if let activeExperiment = insightLabService.activeExperiment {
                    activeExperimentBanner(activeExperiment)
                }

                // Experiment catalog
                if insightLabService.activeExperiment == nil {
                    experimentListSection
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .supportScreen()
        .navigationTitle("Insight Lab")
        .sheet(item: $selectedExperiment) { experiment in
            ExperimentStartConfirmationView(
                experiment: experiment,
                isStarting: isStarting,
                onStart: {
                    Task {
                        await startExperiment(experiment)
                    }
                },
                onCancel: {
                    selectedExperiment = nil
                }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
        .safeAreaInset(edge: .bottom) {
                if startError != nil {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                    if let error = startError {
                        Text(error)
                    }

                    Button("OK") {
                        startError = nil
                    }
                }
                    .foregroundStyle(SupportTheme.textSecondary)
                    .buttonStyle(.supportSecondary)
                    .supportCard()
                    .padding(SupportTheme.Spacing.m)
                }
            }
        .task {
            await insightLabService.fetchActiveExperiment()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Run 7-Day Experiments")
                .font(.title2)
                .fontWeight(.bold)

            Text("Test how different habits affect your mood and energy. Choose an experiment to begin your journey.")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    // MARK: - Active Experiment Banner

    private func activeExperimentBanner(_ experiment: InsightExperiment) -> some View {
        NavigationLink(destination: ExperimentProgressView()) {
            HStack(spacing: SupportTheme.Spacing.m) {
                if let actionType = experiment.actionTypeEnum {
                    Image(systemName: actionType.icon)
                        .font(.title2)
                        .foregroundStyle(SupportTheme.onAccent)
                        .frame(width: 50, height: 50)
                        .background(SupportTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(experiment.title)
                        .font(.headline)
                        .foregroundStyle(SupportTheme.textPrimary)

                    Text("Day \(experiment.currentDay) of 7")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)

                    // Progress bar
                    ProgressView(value: Double(experiment.completedDays), total: 7)
                        .tint(SupportTheme.accent)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .supportCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Experiment List

    private var experimentListSection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
            Text("Available Experiments")
                .font(.headline)
                .padding(.top, SupportTheme.Spacing.xs)

            ForEach(ExperimentActionType.allCases) { actionType in
                ExperimentCard(
                    actionType: actionType,
                    isLoading: isStarting && selectedExperiment == actionType
                ) {
                    selectedExperiment = actionType
                }
            }
        }
    }

    // MARK: - Actions

    private func startExperiment(_ actionType: ExperimentActionType) async {
        print("[ExperimentCatalogView] startExperiment called for: \(actionType.rawValue)")
        isStarting = true
        startError = nil

        do {
            let experiment = try await insightLabService.startExperiment(actionType: actionType)
            print("[ExperimentCatalogView] Experiment started successfully: \(experiment.title)")
            print("[ExperimentCatalogView] activeExperiment after start: \(insightLabService.activeExperiment?.title ?? "nil")")
            selectedExperiment = nil
            print("[ExperimentCatalogView] Sheet dismissed, selectedExperiment cleared")
        } catch {
            print("[ExperimentCatalogView] Failed to start experiment: \(error)")
            startError = "Failed to start experiment: \(error.localizedDescription)"
        }

        isStarting = false
    }
}

// MARK: - Experiment Start Confirmation View

struct ExperimentStartConfirmationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let experiment: ExperimentActionType
    let isStarting: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            // Title
            Text("Start Experiment")
                .font(.title3)
                .accessibilityAddTraits(.isHeader)
                .fontWeight(.semibold)

            // Message
            Text("You'll track this habit for 7 days and see how it affects your mood. Ready to begin?")
                .font(.body)
                .foregroundStyle(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SupportTheme.Spacing.m)

            // Buttons
            VStack(spacing: SupportTheme.Spacing.s) {
                Button(action: onStart) {
                    HStack {
                        if isStarting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: SupportTheme.textPrimary))
                                .scaleEffect(0.8)
                        }
                        Text(isStarting ? "Starting..." : "Start \(experiment.title)")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.supportPrimary)
                .disabled(isStarting)

                Button(action: onCancel) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SupportTheme.Spacing.m)
                        .background(SupportTheme.separator)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .disabled(isStarting)
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
        }
        .padding(.vertical, SupportTheme.Spacing.l)
        .padding(.horizontal, SupportTheme.Spacing.xs)
    }
}

// MARK: - Experiment Card

struct ExperimentCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let actionType: ExperimentActionType
    let isLoading: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack(spacing: SupportTheme.Spacing.s) {
                // Icon
                Image(systemName: actionType.icon)
                    .font(.title2)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(iconColor)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))

                // Title and description
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(actionType.title)
                        .font(.headline)

                    Text(actionType.description)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            // Start button
            Button(action: onStart) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: SupportTheme.textPrimary))
                            .scaleEffect(0.8)
                    }
                    Text(isLoading ? "Starting..." : "Start Experiment")
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.supportPrimary)
            .disabled(isLoading)
        }
        .supportCard()
    }

    private var iconColor: Color {
        switch actionType.color {
        case "green": return SupportTheme.accent
        case "purple": return SupportTheme.accent
        case "indigo": return SupportTheme.accent
        case "orange": return SupportTheme.accent
        case "cyan": return SupportTheme.accent
        case "teal": return SupportTheme.accent
        case "red": return .red
        default: return SupportTheme.accent
        }
    }
}

#Preview {
    NavigationStack {
        ExperimentCatalogView()
    }
}
