// InsightLabView.swift
// Main view for the Insight Lab feature - shows catalog or active experiment

import SwiftUI

struct InsightLabView: View {
    @EnvironmentObject private var insightLabService: InsightLabService
    @EnvironmentObject private var container: DependencyContainer
    @State private var showingCompletedExperiments = false
    @State private var showingStressSignature = false

    var body: some View {
        Group {
            if let experiment = insightLabService.activeExperiment {
                let _ = print("[InsightLabView] Showing experiment: \(experiment.title), status: \(experiment.status)")
                if experiment.status == .completed {
                    // Show report for completed experiment
                    ExperimentReportView(experimentId: experiment.id)
                        .id("report-\(experiment.id)")
                } else {
                    // Show progress view for active experiment
                    ExperimentProgressView()
                        .id("progress-\(experiment.id)")
                }
            } else {
                let _ = print("[InsightLabView] No active experiment, showing catalog")
                // Show catalog when no active experiment
                ExperimentCatalogView()
                    .id("catalog")
            }
        }
        .navigationTitle("Insight Lab")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingCompletedExperiments = true
                    } label: {
                        Label("Past Experiments", systemImage: "clock.arrow.circlepath")
                    }

                    Button {
                        showingStressSignature = true
                    } label: {
                        Label("Stress Signature", systemImage: "chart.bar.xaxis")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingCompletedExperiments) {
            CompletedExperimentsView()
        }
        .sheet(isPresented: $showingStressSignature) {
            NavigationStack {
                StressSignatureView(dataService: container.supabaseDataService)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingStressSignature = false
                            }
                        }
                    }
            }
        }
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
    NavigationStack {
        InsightLabView()
    }
    .environmentObject(DependencyContainer.shared.insightLabService)
}
