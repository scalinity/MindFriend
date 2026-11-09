import SwiftUI

struct PathwayDashboardView: View {
    @EnvironmentObject var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss
    @State private var userPathway: UserPathway

    @State private var dailyContent: DailyPathwayContent?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDailyView = false
    @State private var showPhaseProgress = false
    @State private var showCompletion = false

    init(userPathway: UserPathway) {
        _userPathway = State(initialValue: userPathway)
    }

    var body: some View {
        Group {
            // Show completion view if pathway is completed
            if userPathway.status == .completed {
                PathwayCompletionView(userPathway: userPathway)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.m) {
                        // Header
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            Text(userPathway.pathway?.name ?? "Transition Pathway")
                                .font(.title2.weight(.bold))
                            Text("Day \(userPathway.currentDay) of \(userPathway.totalDays)")
                                .font(.subheadline)
                                .foregroundColor(SupportTheme.textSecondary)
                        }

                        // Progress bar
                        ProgressView(value: userPathway.progressPercentage)
                            .tint(SupportTheme.accent)

                        // Current phase
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            HStack {
                                Text("Current Phase: \(userPathway.currentPhaseName)")
                                    .font(.headline)

                                Spacer()

                                NavigationLink(destination: PhaseProgressView(userPathway: userPathway, transitionService: container.transitionService)) {
                                    HStack(spacing: SupportTheme.Spacing.xxs) {
                                        Text("Details")
                                            .font(.subheadline)
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                    }
                                    .foregroundColor(SupportTheme.accent)
                                }
                            }

                            if let phases = userPathway.pathway?.phases {
                                HStack(spacing: SupportTheme.Spacing.s) {
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
                        .supportCard()

                        // Today's Content
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Today's Content")
                                .font(.headline)

                            if isLoading {
                                HStack {
                                    ProgressView()
                                    Text("Loading...")
                                        .foregroundColor(SupportTheme.textSecondary)
                                }
                            } else if let error = errorMessage {
                                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
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
                                                .foregroundColor(SupportTheme.textSecondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .supportCard()
                                }
                                .disabled(dailyContent == nil)
                            }
                        }
                    }
                    .padding(SupportTheme.Spacing.m)
                }
            }
        }
        .supportScreen()
        .navigationTitle(userPathway.pathway?.name ?? "Pathway")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showDailyView, onDismiss: {
            Task { await refreshAfterCheckIn() }
        }) {
            if let content = dailyContent {
                NavigationStack {
                    DailyTransitionView(userPathway: userPathway, content: content)
                        .environmentObject(container)
                }
            }
        }
        .task {
            await loadDailyContent()
        }
    }

    func loadDailyContent() async {
        isLoading = true
        errorMessage = nil

        do {
            let content = try await container.transitionService.getDailyContent(
                userPathwayId: userPathway.id
            )
            // Validate cached content matches current day; if stale, clear and refetch
            if content.dayNumber != userPathway.currentDay {
                container.transitionService.clearDailyContentCache(for: userPathway.id)
                dailyContent = try await container.transitionService.getDailyContent(
                    userPathwayId: userPathway.id
                )
            } else {
                dailyContent = content
            }
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Failed to load daily content. Please try again."
        }
    }

    func refreshAfterCheckIn() async {
        // Reload the user pathway to get updated current_day
        do {
            let pathways = try await container.transitionService.fetchActivePathways()
            if let updated = pathways.first(where: { $0.id == userPathway.id }) {
                userPathway = updated
            }
        } catch {
            print("[PathwayDashboard] Failed to refresh pathway: \(error)")
        }
        // Reload daily content for the new day
        await loadDailyContent()
    }
}

struct PhaseIndicator: View {
    let phase: PathwayPhaseOverview
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xxs) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 40, height: 40)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundColor(SupportTheme.textPrimary)
                } else {
                    Text("\(phase.number)")
                        .foregroundColor(isActive ? SupportTheme.onAccent : SupportTheme.textPrimary)
                        .font(.caption.weight(.bold))
                }
            }

            Text(phase.name)
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    var backgroundColor: Color {
        if isCompleted { return SupportTheme.accent }
        if isActive { return SupportTheme.accent }
        return SupportTheme.textSecondary.opacity(0.3)
    }
}
