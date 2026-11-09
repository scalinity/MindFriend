import SwiftUI

/// Displays a seasonal event with progress tracking
struct SeasonalEventCard: View {
    let event: SeasonalEvent
    let participation: EventParticipation?
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: eventIcon)
                            .foregroundColor(SupportTheme.Celebration.gold)

                        Text(event.name)
                            .font(.headline)
                    }

                    Text(event.timeRemainingText)
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }

                Spacer()

                if event.xpMultiplier > 1.0 {
                    Text("\(Int(event.xpMultiplier))x XP")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(SupportTheme.accent)
                        .padding(.horizontal, SupportTheme.Spacing.xs)
                        .padding(.vertical, SupportTheme.Spacing.xxs)
                        .background(SupportTheme.accent.opacity(0.15))
                        .cornerRadius(SupportTheme.controlRadius)
                }
            }

            // Description
            if let description = event.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Progress or Join button
            if let participation = participation {
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(SupportTheme.separator)
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(progressColor)
                                .frame(
                                    width: geometry.size.width * progressPercentage,
                                    height: 8
                                )
                        }
                    }
                    .frame(height: 8)

                    // Progress text
                    HStack {
                        Text("\(participation.progress)/\(event.targetCount)")
                            .font(.caption)
                            .foregroundColor(SupportTheme.textSecondary)

                        Spacer()

                        if participation.isCompleted {
                            Label("Completed", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(SupportTheme.accent)
                        } else {
                            Text("\(event.targetCount - participation.progress) remaining")
                                .font(.caption)
                                .foregroundColor(SupportTheme.textSecondary)
                        }
                    }
                }
            } else {
                Button(action: onJoin) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Join Challenge")
                    }
                }
                .buttonStyle(.supportPrimary)
            }
        }
        .supportCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Computed Properties

    private var eventIcon: String {
        switch event.requiredActivityType {
        case "journaling": return "pencil.and.scribble"
        case "meditation": return "sparkles"
        case "movement": return "figure.walk"
        case "breathing": return "wind"
        case "grounding": return "leaf.fill"
        default: return "star.fill"
        }
    }

    private var progressPercentage: Double {
        guard let participation = participation else { return 0 }
        return min(1.0, Double(participation.progress) / Double(event.targetCount))
    }

    private var progressColor: Color {
        if participation?.isCompleted == true {
            return SupportTheme.accent
        }
        return SupportTheme.accent
    }

    private var accessibilityDescription: String {
        var description = "\(event.name). \(event.timeRemainingText)."
        if let participation = participation {
            description += " Progress: \(participation.progress) of \(event.targetCount)."
            if participation.isCompleted {
                description += " Completed"
            }
        } else {
            description += " Not joined. Double tap to join."
        }
        return description
    }
}

/// Compact event indicator for home screen
struct EventIndicatorView: View {
    let event: SeasonalEvent
    let progress: Int?
    let targetCount: Int

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: "leaf")
                .foregroundColor(SupportTheme.Celebration.gold)

            Text(event.name)
                .font(.caption)
                .fontWeight(.medium)

            if let progress = progress {
                Text("\(progress)/\(targetCount)")
                    .font(.caption)
                    .foregroundColor(SupportTheme.textSecondary)
            }

            Text(event.timeRemainingText)
                .font(.caption2)
                .foregroundColor(SupportTheme.textSecondary)
        }
        .padding(.horizontal, SupportTheme.Spacing.s)
        .padding(.vertical, SupportTheme.Spacing.xs)
        .background(SupportTheme.Celebration.gold.opacity(0.1))
        .cornerRadius(SupportTheme.cardRadius)
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.m) {
        // Not joined
        SeasonalEventCard(
            event: SeasonalEvent(
                id: "1",
                name: "30 Days of Gratitude",
                description: "Write a gratitude journal entry every day in November",
                startsAt: Date(),
                endsAt: Calendar.current.date(byAdding: .day, value: 18, to: Date())!,
                eventType: "challenge",
                requiredActivityType: "journaling",
                rewardBadgeId: nil,
                targetCount: 30,
                xpMultiplier: 1.0,
                createdAt: Date()
            ),
            participation: nil,
            onJoin: {}
        )

        // In progress
        SeasonalEventCard(
            event: SeasonalEvent(
                id: "2",
                name: "New Year Mindfulness",
                description: "Start the year with daily meditation",
                startsAt: Date(),
                endsAt: Calendar.current.date(byAdding: .day, value: 10, to: Date())!,
                eventType: "challenge",
                requiredActivityType: "meditation",
                rewardBadgeId: nil,
                targetCount: 31,
                xpMultiplier: 1.5,
                createdAt: Date()
            ),
            participation: EventParticipation(
                id: "p1",
                userId: "u1",
                eventId: "2",
                progress: 12,
                completedAt: nil,
                joinedAt: Date()
            ),
            onJoin: {}
        )

        // Completed
        SeasonalEventCard(
            event: SeasonalEvent(
                id: "3",
                name: "Spring Renewal",
                description: "Focus on movement and outdoor activities",
                startsAt: Date(),
                endsAt: Calendar.current.date(byAdding: .day, value: 5, to: Date())!,
                eventType: "challenge",
                requiredActivityType: "movement",
                rewardBadgeId: nil,
                targetCount: 30,
                xpMultiplier: 1.0,
                createdAt: Date()
            ),
            participation: EventParticipation(
                id: "p2",
                userId: "u1",
                eventId: "3",
                progress: 30,
                completedAt: Date(),
                joinedAt: Date()
            ),
            onJoin: {}
        )

        EventIndicatorView(
            event: SeasonalEvent(
                id: "1",
                name: "30 Days of Gratitude",
                description: nil,
                startsAt: Date(),
                endsAt: Calendar.current.date(byAdding: .day, value: 18, to: Date())!,
                eventType: "challenge",
                requiredActivityType: "journaling",
                rewardBadgeId: nil,
                targetCount: 30,
                xpMultiplier: 1.0,
                createdAt: Date()
            ),
            progress: 12,
            targetCount: 30
        )
    }
    .padding(SupportTheme.Spacing.m)
}
