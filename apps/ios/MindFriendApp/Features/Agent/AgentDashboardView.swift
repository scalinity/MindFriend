import SwiftUI

struct AgentDashboardView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel = AgentDashboardViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Agent Status Header
                    agentStatusHeader

                    if let dashboardData = viewModel.dashboardData {
                        // Active Signals Section
                        if !dashboardData.activeSignals.isEmpty {
                            activeSignalsSection(signals: dashboardData.activeSignals)
                        }

                        // Recent Actions Section
                        recentActionsSection(actions: dashboardData.recentActions)

                        // Learnings Summary (if available)
                        if !viewModel.learnings.isEmpty {
                            learningSummarySection
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Wellness Agent")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                Task {
                    await viewModel.loadData(service: dependencies.agentService)
                }
            }) {
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
            .alert("Error", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
                Button("OK") {
                    viewModel.errorMessage = nil
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Agent Status Header

    private var agentStatusHeader: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.dashboardData?.isAgentActive == true ? Color.green : Color.gray)
                            .frame(width: 12, height: 12)

                        Text(viewModel.dashboardData?.isAgentActive == true ? "Agent Active" : "Agent Paused")
                            .font(.headline)
                    }

                    if let settings = viewModel.dashboardData?.settings {
                        Text(settings.autonomyLevel.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if let data = viewModel.dashboardData {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(data.actionsToday)/\(data.settings.maxDailyOutreach)")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Actions Today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    // MARK: - Active Signals Section

    private func activeSignalsSection(signals: [AgentSignal]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Signals")
                    .font(.headline)

                Spacer()

                Text("\(signals.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(signals) { signal in
                SignalIndicatorView(signal: signal)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    // MARK: - Recent Actions Section

    private func recentActionsSection(actions: [AgentAction]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Actions")
                    .font(.headline)

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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
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
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
    }

    // MARK: - Learning Summary Section

    private var learningSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Learnings")
                .font(.headline)

            Text("Your agent has learned from \(viewModel.totalSamples) interactions")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(viewModel.learnings.prefix(3)) { learning in
                HStack {
                    Image(systemName: "brain")
                        .foregroundStyle(.purple)

                    VStack(alignment: .leading) {
                        Text(learning.learningType.displayName)
                            .font(.subheadline)

                        Text("Confidence: \(Int(learning.confidence * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(learning.sampleCount) samples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
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
