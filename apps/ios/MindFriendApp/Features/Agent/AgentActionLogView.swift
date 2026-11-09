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
                .listRowBackground(SupportTheme.surface)
            }

            if viewModel.actions.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Actions Yet",
                    systemImage: "bell.slash",
                    description: Text(
                        "The agent hasn't taken any actions yet. Enable the agent and it will start monitoring your patterns."
                    )
                )
            }
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
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
        let grouped = Dictionary(grouping: viewModel.actions.filter { $0.actionType != .streakReminder }) { action in
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
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: action.actionType.iconName)
                .font(.title3)
                .foregroundStyle(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(action.content.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(action.content.body)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .lineLimit(2)

                HStack(spacing: SupportTheme.Spacing.xs) {
                    Text(action.status.displayName)
                        .font(.caption2)
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(statusColor.opacity(0.2))
                        .foregroundStyle(statusColor)
                        .clipShape(Capsule())

                    Text(timeAgo)
                        .font(.caption2)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
            }

            Spacer()

            if let score = action.effectivenessScore {
                VStack {
                    Image(systemName: score > 0.5 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                        .foregroundStyle(score > 0.5 ? SupportTheme.accent : SupportTheme.accent)
                }
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xxs)
    }

    private var statusColor: Color {
        switch action.status {
        case .planned, .scheduled:
            return SupportTheme.accent
        case .delivered:
            return SupportTheme.accent
        case .opened:
            return SupportTheme.Celebration.gold
        case .responded:
            return SupportTheme.accent
        case .dismissed:
            return SupportTheme.textSecondary
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
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.l) {
                    // Header
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                        HStack {
                            Image(systemName: action.actionType.iconName)
                                .font(.title2)
                            Text(action.actionType.displayName)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                        }

                        Text(action.content.title)
                            .font(.title3)
                            .accessibilityAddTraits(.isHeader)
                            .fontWeight(.semibold)

                        Text(action.content.body)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }

                    Divider()

                    // Status Timeline
                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                        Text("Status")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        HStack {
                            ActionStatusBadge(status: action.status)
                            Spacer()
                            if let delivered = action.deliveredAt {
                                Text("Delivered: \(formatted(delivered))")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }
                        }
                    }

                    // Reasoning
                    if let reasoning = action.reasoning {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                            HStack {
                                Image(systemName: "brain")
                                Text("Why did I get this?")
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                            }

                            Text(reasoning)
                                .font(.subheadline)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }
                        .padding()
                        .background(SupportTheme.field)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                    }

                    // Feedback Section
                    if action.effectivenessScore == nil && action.status.isTerminal {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Was this helpful?")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

                            HStack(spacing: SupportTheme.Spacing.m) {
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
                                .buttonStyle(.supportSecondary)
                                .tint(SupportTheme.accent)

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
                                .buttonStyle(.supportSecondary)
                                .tint(SupportTheme.accent)
                            }
                        }
                    }

                    // Quick Actions
                    if let quickActions = action.content.quickActions, !quickActions.isEmpty {
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
                            Text("Quick Actions")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)

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
                                .buttonStyle(.supportSecondary)
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .supportScreen()
            .foregroundStyle(SupportTheme.textPrimary)
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
            .padding(.horizontal, SupportTheme.Spacing.xs)
            .padding(.vertical, SupportTheme.Spacing.xxs)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .planned, .scheduled: return SupportTheme.accent
        case .delivered: return SupportTheme.accent
        case .opened: return SupportTheme.Celebration.gold
        case .responded: return SupportTheme.accent
        case .dismissed: return SupportTheme.textSecondary
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
