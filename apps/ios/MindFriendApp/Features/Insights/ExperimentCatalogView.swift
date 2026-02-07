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
            VStack(alignment: .leading, spacing: 24) {
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
            .padding()
        }
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
        .alert("Error", isPresented: Binding(get: { startError != nil }, set: { if !$0 { startError = nil } })) {
            Button("OK") {
                startError = nil
            }
        } message: {
            if let error = startError {
                Text(error)
            }
        }
        .task {
            await insightLabService.fetchActiveExperiment()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Run 7-Day Experiments")
                .font(.title2)
                .fontWeight(.bold)

            Text("Test how different habits affect your mood and energy. Choose an experiment to begin your journey.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Active Experiment Banner

    private func activeExperimentBanner(_ experiment: InsightExperiment) -> some View {
        NavigationLink(destination: ExperimentProgressView()) {
            HStack(spacing: 16) {
                if let actionType = experiment.actionTypeEnum {
                    Image(systemName: actionType.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(experiment.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Day \(experiment.currentDay) of 7")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Progress bar
                    ProgressView(value: Double(experiment.completedDays), total: 7)
                        .tint(.accentColor)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Experiment List

    private var experimentListSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Available Experiments")
                .font(.headline)
                .padding(.top, 8)

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
    let experiment: ExperimentActionType
    let isStarting: Bool
    let onStart: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Start Experiment")
                .font(.title3)
                .fontWeight(.semibold)
            
            // Message
            Text("You'll track this habit for 7 days and see how it affects your mood. Ready to begin?")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: onStart) {
                    HStack {
                        if isStarting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        }
                        Text(isStarting ? "Starting..." : "Start \(experiment.title)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isStarting)
                
                Button(action: onCancel) {
                    Text("Cancel")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(.systemGray5))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isStarting)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 8)
    }
}

// MARK: - Experiment Card

struct ExperimentCard: View {
    let actionType: ExperimentActionType
    let isLoading: Bool
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: actionType.icon)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(iconColor)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                // Title and description
                VStack(alignment: .leading, spacing: 4) {
                    Text(actionType.title)
                        .font(.headline)

                    Text(actionType.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            // Start button
            Button(action: onStart) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    Text(isLoading ? "Starting..." : "Start Experiment")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isLoading)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var iconColor: Color {
        switch actionType.color {
        case "green": return .green
        case "purple": return .purple
        case "indigo": return .indigo
        case "orange": return .orange
        case "cyan": return .cyan
        case "teal": return .teal
        case "red": return .red
        default: return .accentColor
        }
    }
}

#Preview {
    NavigationStack {
        ExperimentCatalogView()
    }
}
