import SwiftUI

struct PathwayDashboardView: View {
    @EnvironmentObject var container: DependencyContainer
    let userPathway: UserPathway

    @State private var dailyContent: DailyPathwayContent?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDailyView = false
    @State private var showPhaseProgress = false
    @State private var showCompletion = false

    var body: some View {
        // Show completion view if pathway is completed
        if userPathway.status == .completed {
            PathwayCompletionView(userPathway: userPathway)
        } else {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(userPathway.pathway?.name ?? "Transition Pathway")
                        .font(.title2.weight(.bold))
                    Text("Day \(userPathway.currentDay) of \(userPathway.totalDays)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Progress bar
                ProgressView(value: userPathway.progressPercentage)
                    .tint(Color.blue)

                // Current phase
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Current Phase: \(userPathway.currentPhaseName)")
                            .font(.headline)

                        Spacer()

                        NavigationLink(destination: PhaseProgressView(userPathway: userPathway, transitionService: container.transitionService)) {
                            HStack(spacing: 4) {
                                Text("Details")
                                    .font(.subheadline)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                            }
                            .foregroundColor(.blue)
                        }
                    }

                    if let phases = userPathway.pathway?.phases {
                        HStack(spacing: 12) {
                            ForEach(phases) { phase in
                                PhaseIndicator(
                                    phase: phase,
                                    isActive: phase.number == userPathway.currentPhase,
                                    isCompleted: phase.number < userPathway.currentPhase
                                )
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Today's Content
                VStack(alignment: .leading, spacing: 12) {
                    Text("Today's Content")
                        .font(.headline)

                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading...")
                                .foregroundColor(.secondary)
                        }
                    } else if let error = errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                            Button("Retry") {
                                Task { await loadDailyContent() }
                            }
                            .font(.caption)
                        }
                    } else {
                        Button(action: { showDailyView = true }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Day \(dailyContent?.dayNumber ?? userPathway.currentDay)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(dailyContent?.theme.title ?? "Daily Check-In")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .disabled(dailyContent == nil)
                    }
                }
            }
            .padding()
        }
        .sheet(isPresented: $showDailyView) {
            if let content = dailyContent {
                DailyTransitionView(userPathway: userPathway, content: content)
                    .environmentObject(container)
            }
        }
        .task {
            await loadDailyContent()
        }
        }
    }

    func loadDailyContent() async {
        isLoading = true
        errorMessage = nil

        do {
            dailyContent = try await container.transitionService.getDailyContent(
                userPathwayId: userPathway.id
            )
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to load daily content. Please try again."
        }
    }
}

struct PhaseIndicator: View {
    let phase: PathwayPhaseOverview
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                } else {
                    Text("\(phase.number)")
                        .foregroundColor(isActive ? .white : .primary)
                        .font(.caption.weight(.bold))
                }
            }

            Text(phase.name)
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    var backgroundColor: Color {
        if isCompleted { return Color.green }
        if isActive { return Color.blue }
        return Color.gray.opacity(0.3)
    }
}
