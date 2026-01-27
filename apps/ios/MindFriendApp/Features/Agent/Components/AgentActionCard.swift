import SwiftUI

struct AgentActionCard: View {
    let action: AgentAction
    let onHelpful: ((Bool) -> Void)?

    init(action: AgentAction, onHelpful: ((Bool) -> Void)? = nil) {
        self.action = action
        self.onHelpful = onHelpful
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: action.actionType.iconName)
                    .foregroundStyle(typeColor)

                Text(action.actionType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(action.content.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(action.content.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Status and Actions
            HStack {
                StatusPill(status: action.status)

                Spacer()

                if action.effectivenessScore == nil && action.status.isTerminal {
                    HStack(spacing: 8) {
                        Button {
                            onHelpful?(true)
                        } label: {
                            Image(systemName: "hand.thumbsup")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)

                        Button {
                            onHelpful?(false)
                        } label: {
                            Image(systemName: "hand.thumbsdown")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                } else if let score = action.effectivenessScore {
                    HStack(spacing: 4) {
                        Image(systemName: score > 0.5 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                            .foregroundStyle(score > 0.5 ? .green : .orange)
                        Text(score > 0.5 ? "Helpful" : "Not helpful")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var typeColor: Color {
        switch action.actionType {
        case .checkIn: return .blue
        case .suggestExercise: return .green
        case .morningBriefing: return .orange
        case .encouragement: return .yellow
        case .streakReminder: return .red
        case .moodPrompt: return .purple
        case .contentRecommendation: return .cyan
        case .concernAlert: return .pink
        }
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: action.createdAt, relativeTo: Date())
    }
}

struct StatusPill: View {
    let status: ActionStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
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

#Preview {
    VStack(spacing: 16) {
        AgentActionCard(
            action: AgentAction(
                id: UUID(),
                userId: UUID(),
                signalId: nil,
                actionType: .checkIn,
                status: .delivered,
                scheduledFor: Date(),
                deliveredAt: Date(),
                content: ActionContent(
                    title: "Hey, checking in",
                    body: "I noticed your mood has been lower lately. Want to talk about it?",
                    quickActions: nil,
                    deepLink: nil,
                    metadata: nil
                ),
                channel: "push",
                reasoning: "Mood declined over 3 days",
                userResponse: nil,
                effectivenessScore: nil,
                createdAt: Date().addingTimeInterval(-3600),
                updatedAt: Date()
            ),
            onHelpful: { _ in }
        )

        AgentActionCard(
            action: AgentAction(
                id: UUID(),
                userId: UUID(),
                signalId: nil,
                actionType: .encouragement,
                status: .responded,
                scheduledFor: Date(),
                deliveredAt: Date(),
                content: ActionContent(
                    title: "You're doing great!",
                    body: "Your 7-day streak is amazing. Keep up the good work!",
                    quickActions: nil,
                    deepLink: nil,
                    metadata: nil
                ),
                channel: "push",
                reasoning: "Positive momentum detected",
                userResponse: nil,
                effectivenessScore: 1.5,
                createdAt: Date().addingTimeInterval(-86400),
                updatedAt: Date()
            )
        )
    }
    .padding()
}
