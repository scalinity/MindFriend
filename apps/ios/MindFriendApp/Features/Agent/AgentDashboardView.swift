import SwiftUI

struct AgentDashboardView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel = AgentDashboardViewModel()
    @State private var showSettings = false

    /// Set by the stable shell so pushed work adds no second NavigationStack; standalone callers keep their own.
    @Environment(\.supportRootEmbedded) private var supportEmbedded

    var body: some View {
        SupportRootNavigation(embedded: supportEmbedded) {
            ScrollView {
                VStack(spacing: SupportTheme.Spacing.l) {
                    if let error = viewModel.errorMessage {
                        SupportUnavailableState(
                            title: "Wellness agent unavailable", message: error,
                            actionTitle: "Try again",
                            action: { Task { await viewModel.loadData(service: dependencies.agentService) } })
                    }
                    // Agent Status Header
                    agentStatusHeader

                    if let dashboardData = viewModel.dashboardData {
                        // Active Signals Section
                        if !dashboardData.activeSignals.isEmpty {
                            activeSignalsSection(
                                signals: dashboardData.activeSignals.filter { $0.signalType != .streakRisk })
                        }

                        // Recent Actions Section
                        recentActionsSection(
                            actions: dashboardData.recentActions.filter { $0.actionType != .streakReminder })

                        // Learnings Summary (if available)
                        if !viewModel.learnings.isEmpty {
                            learningSummarySection
                        }
                    }
                }
                .padding()
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
            .navigationTitle("Wellness Agent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Wellness agent settings")
                }
            }
            .sheet(
                isPresented: $showSettings,
                onDismiss: {
                    Task {
                        await viewModel.loadData(service: dependencies.agentService)
                    }
                }
            ) {
                AgentSettingsView()
                    .environmentObject(dependencies)
            }
            .refreshable {
                await viewModel.loadData(service: dependencies.agentService)
            }
            .task {
                await viewModel.loadData(service: dependencies.agentService)
            }
            .overlay {
                if viewModel.isLoading && viewModel.dashboardData == nil {
                    ProgressView("Loading...")
                }
            }
        }
    }

    // MARK: - Agent Status Header

    private var agentStatusHeader: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Circle()
                            .fill(
                                viewModel.dashboardData?.isAgentActive == true
                                    ? SupportTheme.accent : SupportTheme.textSecondary
                            )
                            .frame(width: 12, height: 12)

                        Text(viewModel.dashboardData?.isAgentActive == true ? "Agent Active" : "Agent Paused")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }

                    if let settings = viewModel.dashboardData?.settings {
                        Text(settings.autonomyLevel.description)
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }

                Spacer()

                if let data = viewModel.dashboardData {
                    VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                        Text("\(data.actionsToday)/\(data.settings.maxDailyOutreach)")
                            .font(.title2)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.semibold)

                        Text("Actions Today")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }

            if viewModel.dashboardData?.isAgentActive == false {
                Button {
                    Task {
                        await viewModel.enableAgent(service: dependencies.agentService)
                    }
                } label: {
                    HStack {
                        Image(systemName: "bell.badge")
                        Text("Enable Wellness Agent")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.supportPrimary)
            }
        }
        .supportCard()
    }

    // MARK: - Active Signals Section

    private func activeSignalsSection(signals: [AgentSignal]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Text("Active Signals")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Text("\(signals.count)")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            ForEach(signals) { signal in
                SignalIndicatorView(signal: signal)
            }
        }
        .supportCard()
    }

    // MARK: - Recent Actions Section

    private func recentActionsSection(actions: [AgentAction]) -> some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            HStack {
                Text("Recent Actions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                NavigationLink {
                    AgentActionLogView()
                        .environmentObject(dependencies)
                } label: {
                    Text("See All")
                        .font(.subheadline)
                }
            }

            if actions.isEmpty {
                Text("No actions yet")
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SupportTheme.Spacing.l)
            } else {
                ForEach(actions.prefix(5)) { action in
                    AgentActionCard(
                        action: action,
                        onHelpful: { isHelpful in
                            Task {
                                await viewModel.markActionHelpful(
                                    actionId: action.id,
                                    isHelpful: isHelpful,
                                    service: dependencies.agentService
                                )
                            }
                        }
                    )
                }
            }
        }
        .supportCard()
    }

    // MARK: - Learning Summary Section

    private var learningSummarySection: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            Text("Agent Learnings")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            Text("Your agent has learned from \(viewModel.totalSamples) interactions")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)

            ForEach(viewModel.learnings.prefix(3)) { learning in
                HStack {
                    Image(systemName: "brain")
                        .foregroundStyle(SupportTheme.accent)

                    VStack(alignment: .leading) {
                        Text(learning.learningType.displayName)
                            .font(.subheadline)

                        Text("Confidence: \(Int(learning.confidence * 100))%")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Spacer()

                    Text("\(learning.sampleCount) samples")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.vertical, SupportTheme.Spacing.xxs)
            }
        }
        .supportCard()
    }
}

// MARK: - View Model

@MainActor
final class AgentDashboardViewModel: ObservableObject {
    @Published var dashboardData: AgentDashboardData?
    @Published var learnings: [AgentLearning] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    var totalSamples: Int {
        learnings.reduce(0) { $0 + $1.sampleCount }
    }

    func loadData(service: AgentService) async {
        isLoading = true
        defer { isLoading = false }

        do {
            dashboardData = try await service.loadDashboardData()
            learnings = try await service.fetchLearnings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func enableAgent(service: AgentService) async {
        guard var settings = dashboardData?.settings else { return }
        settings.isEnabled = true

        do {
            try await service.updateSettings(settings)
            dashboardData = try await service.loadDashboardData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markActionHelpful(actionId: UUID, isHelpful: Bool, service: AgentService) async {
        do {
            try await service.markActionAsHelpful(actionId: actionId, isHelpful: isHelpful)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AgentDashboardView()
        .environmentObject(DependencyContainer.preview)
}
