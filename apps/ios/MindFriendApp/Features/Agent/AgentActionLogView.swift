import SwiftUI

struct AgentActionLogView: View {
    @EnvironmentObject private var dependencies: DependencyContainer
    @StateObject private var viewModel = AgentActionLogViewModel()
    @State private var selectedAction: AgentAction?

    var body: some View {
        List {
            ForEach(groupedActions, id: \.key) { date, actions in
                Section {
                    ForEach(actions) { action in
                        AgentActionRow(action: action)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedAction = action
                            }
                    }
                } header: {
                    Text(formatDate(date))
                }
            }

            if viewModel.actions.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Actions Yet",
                    systemImage: "bell.slash",
                    description: Text("The agent hasn't taken any actions yet. Enable the agent and it will start monitoring your patterns.")
                )
            }
        }
        .navigationTitle("Action History")
        .refreshable {
            await viewModel.loadActions(service: dependencies.agentService)
        }
        .task {
            await viewModel.loadActions(service: dependencies.agentService)
        }
        .overlay {
            if viewModel.isLoading && viewModel.actions.isEmpty {
                ProgressView()
            }
        }
        .sheet(item: $selectedAction) { action in
            ActionDetailSheet(
                action: action,
                onHelpful: { isHelpful in
                    Task {
                        await viewModel.markHelpful(
                            actionId: action.id,
                            isHelpful: isHelpful,
                            service: dependencies.agentService
                        )
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var groupedActions: [(key: Date, value: [AgentAction])] {
        let grouped = Dictionary(grouping: viewModel.actions) { action in
            Calendar.current.startOfDay(for: action.createdAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    private func formatDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }
}

// MARK: - Action Row

struct AgentActionRow: View {
    let action: AgentAction

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.actionType.iconName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(action.content.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(action.content.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(action.status.displayName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(statusColor.opacity(0.2))
                        .foregroundStyle(statusColor)
                        .clipShape(Capsule())

                    Text(timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let score = action.effectivenessScore {
                VStack {
                    Image(systemName: score > 0.5 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundStyle(score > 0.5 ? .green : .orange)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch action.status {
        case .planned, .scheduled:
            return .blue
        case .delivered:
            return .orange
        case .opened:
            return .yellow
        case .responded:
            return .green
        case .dismissed:
            return .gray
        case .cancelled:
            return .red
        }
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: action.createdAt, relativeTo: Date())
    }
}

// MARK: - Action Detail Sheet

struct ActionDetailSheet: View {
    let action: AgentAction
    let onHelpful: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: action.actionType.iconName)
                                .font(.title2)
                            Text(action.actionType.displayName)
                                .font(.headline)
                        }

                        Text(action.content.title)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(action.content.body)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Status Timeline
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Status")
                            .font(.headline)

                        HStack {
                            ActionStatusBadge(status: action.status)
                            Spacer()
                            if let delivered = action.deliveredAt {
                                Text("Delivered: \(formatted(delivered))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Reasoning
                    if let reasoning = action.reasoning {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "brain")
                                Text("Why did I get this?")
                                    .font(.headline)
                            }

                            Text(reasoning)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Feedback Section
                    if action.effectivenessScore == nil && action.status.isTerminal {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Was this helpful?")
                                .font(.headline)

                            HStack(spacing: 16) {
                                Button {
                                    onHelpful(true)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "hand.thumbsup")
                                        Text("Yes")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)

                                Button {
                                    onHelpful(false)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "hand.thumbsdown")
                                        Text("No")
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                            }
                        }
                    }

                    // Quick Actions
                    if let quickActions = action.content.quickActions, !quickActions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quick Actions")
                                .font(.headline)

                            ForEach(quickActions) { quickAction in
                                Button {
                                    // Handle quick action
                                } label: {
                                    HStack {
                                        Text(quickAction.label)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Action Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ActionStatusBadge: View {
    let status: ActionStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .planned, .scheduled: return .blue
        case .delivered: return .orange
        case .opened: return .yellow
        case .responded: return .green
        case .dismissed: return .gray
        case .cancelled: return .red
        }
    }
}

// MARK: - View Model

@MainActor
final class AgentActionLogViewModel: ObservableObject {
    @Published var actions: [AgentAction] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadActions(service: AgentService) async {
        isLoading = true
        defer { isLoading = false }

        do {
            actions = try await service.fetchRecentActions(limit: 100)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markHelpful(actionId: UUID, isHelpful: Bool, service: AgentService) async {
        do {
            try await service.markActionAsHelpful(actionId: actionId, isHelpful: isHelpful)
            await loadActions(service: service)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        AgentActionLogView()
            .environmentObject(DependencyContainer.preview)
    }
}
