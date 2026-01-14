import SwiftUI

/// Displays a seasonal event with progress tracking
struct SeasonalEventCard: View {
    let event: SeasonalEvent
    let participation: EventParticipation?
    let onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: eventIcon)
                            .foregroundColor(.yellow)

                        Text(event.name)
                            .font(.headline)
                    }

                    Text(event.timeRemainingText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if event.xpMultiplier > 1.0 {
                    Text("\(Int(event.xpMultiplier))x XP")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(8)
                }
            }

            // Description
            if let description = event.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Progress or Join button
            if let participation = participation {
                VStack(alignment: .leading, spacing: 6) {
                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
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
                            .foregroundColor(.secondary)

                        Spacer()

                        if participation.isCompleted {
                            Label("Completed!", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("\(event.targetCount - participation.progress) remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Button(action: onJoin) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Join Challenge")
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
            return .green
        }
        return .accentColor
    }

    private var accessibilityDescription: String {
        var description = "\(event.name). \(event.timeRemainingText)."
        if let participation = participation {
            description += " Progress: \(participation.progress) of \(event.targetCount)."
            if participation.isCompleted {
                description += " Completed!"
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
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundColor(.orange)

            Text(event.name)
                .font(.caption)
                .fontWeight(.medium)

            if let progress = progress {
                Text("\(progress)/\(targetCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(event.timeRemainingText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(20)
    }
}

#Preview {
    VStack(spacing: 16) {
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
    .padding()
}
