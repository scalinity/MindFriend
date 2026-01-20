// InsightLabView.swift
// Main view for the Insight Lab feature - shows catalog or active experiment

import SwiftUI

struct InsightLabView: View {
    @EnvironmentObject private var insightLabService: InsightLabService
    @State private var showingCompletedExperiments = false

    var body: some View {
        NavigationStack {
            Group {
                if let experiment = insightLabService.activeExperiment {
                    if experiment.status == .completed {
                        // Show report for completed experiment
                        ExperimentReportView(experimentId: experiment.id)
                    } else {
                        // Show progress view for active experiment
                        ExperimentProgressView()
                    }
                } else {
                    // Show catalog when no active experiment
                    ExperimentCatalogView()
                }
            }
            .navigationTitle("Insight Lab")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCompletedExperiments = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showingCompletedExperiments) {
                CompletedExperimentsView()
            }
        }
        .environmentObject(insightLabService)
        .task {
            await insightLabService.fetchActiveExperiment()
        }
    }
}

// MARK: - Completed Experiments View

struct CompletedExperimentsView: View {
    @EnvironmentObject private var insightLabService: InsightLabService
    @State private var completedExperiments: [InsightExperiment] = []
    @State private var isLoading = true
    @State private var selectedExperimentId: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                } else if completedExperiments.isEmpty {
                    ContentUnavailableView(
                        "No Completed Experiments",
                        systemImage: "flask",
                        description: Text("Your completed experiments will appear here.")
                    )
                } else {
                    List(completedExperiments) { experiment in
                        Button {
                            selectedExperimentId = experiment.id
                        } label: {
                            HStack(spacing: 12) {
                                if let actionType = experiment.actionTypeEnum {
                                    Image(systemName: actionType.icon)
                                        .font(.title3)
                                        .foregroundStyle(.white)
                                        .frame(width: 40, height: 40)
                                        .background(Color.accentColor)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(experiment.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    if let endedAt = experiment.endedAt {
                                        Text("Completed \(endedAt, style: .relative) ago")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Past Experiments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedExperimentId) { experimentId in
                NavigationStack {
                    ExperimentReportView(experimentId: experimentId)
                }
            }
        }
        .task {
            await loadCompletedExperiments()
        }
    }

    private func loadCompletedExperiments() async {
        isLoading = true
        do {
            completedExperiments = try await insightLabService.fetchCompletedExperiments()
        } catch {
            print("Failed to load completed experiments: \(error)")
        }
        isLoading = false
    }
}

// MARK: - UUID Extension for Identifiable

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

#Preview {
    InsightLabView()
        .environmentObject(DependencyContainer.shared.insightLabService)
}
