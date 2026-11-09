import SwiftUI

struct AgentActionCard: View {
    let action: AgentAction
    let onHelpful: ((Bool) -> Void)?

    init(action: AgentAction, onHelpful: ((Bool) -> Void)? = nil) {
        self.action = action
        self.onHelpful = onHelpful
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Header
            HStack {
                Image(systemName: action.actionType.iconName)
                    .foregroundStyle(typeColor)

                Text(action.actionType.displayName)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                Spacer()

                Text(timeAgo)
                    .font(.caption2)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            // Content
            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(action.content.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(action.content.body)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .lineLimit(2)
            }

            // Status and Actions
            HStack {
                StatusPill(status: action.status)

                Spacer()

                if action.effectivenessScore == nil && action.status.isTerminal {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Button {
                            onHelpful?(true)
                        } label: {
                            Image(systemName: "hand.thumbsup")
                                .font(.caption)
                        }
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Helpful")
                        .buttonStyle(.supportSecondary)
                        .tint(SupportTheme.accent)

                        Button {
                            onHelpful?(false)
                        } label: {
                            Image(systemName: "hand.thumbsdown")
                                .font(.caption)
                        }
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Not helpful")
                        .buttonStyle(.supportSecondary)
                        .tint(SupportTheme.accent)
                    }
                } else if let score = action.effectivenessScore {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: score > 0.5 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                            .foregroundStyle(score > 0.5 ? SupportTheme.accent : SupportTheme.accent)
                        Text(score > 0.5 ? "Helpful" : "Not helpful")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
            }
        }
        .supportCard()
    }

    private var typeColor: Color {
        switch action.actionType {
        case .checkIn: return SupportTheme.accent
        case .suggestExercise: return SupportTheme.accent
        case .morningBriefing: return SupportTheme.accent
        case .encouragement: return SupportTheme.Celebration.gold
        case .streakReminder: return .red
        case .moodPrompt: return SupportTheme.accent
        case .contentRecommendation: return SupportTheme.accent
        case .concernAlert: return SupportTheme.accent
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

#Preview {
    VStack(spacing: SupportTheme.Spacing.m) {
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
                    body: "You made time for yourself this week. Here is a moment to reflect.",
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
