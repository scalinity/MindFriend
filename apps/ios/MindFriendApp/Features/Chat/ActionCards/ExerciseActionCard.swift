import SwiftUI

struct ExerciseActionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let card: ActionCard

    var body: some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.s))
            : AnyLayout(HStackLayout(spacing: SupportTheme.Spacing.s))) {
            ZStack {
                Circle()
                    .fill(SupportTheme.accent.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: card.cardData.icon)
                    .font(.system(size: 20))
                    .foregroundColor(SupportTheme.accent)
            }

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(card.cardData.title)
                    .font(.headline)
                    .foregroundColor(SupportTheme.textPrimary)

                Text(card.cardData.description)
                    .font(.subheadline)
                    .foregroundColor(SupportTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: SupportTheme.Spacing.xs) {
                    Label("\(card.cardData.estimatedMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(SupportTheme.textSecondary)
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

struct PremiumLockedCard: View {
    let card: ActionCard
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            HStack(spacing: SupportTheme.Spacing.s) {
                ZStack {
                    Circle()
                        .fill(SupportTheme.textSecondary.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: card.cardData.icon)
                        .font(.system(size: 20))
                        .foregroundColor(SupportTheme.textSecondary)
                        .blur(radius: 3)
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(card.cardData.title)
                        .font(.headline)
                        .foregroundColor(SupportTheme.textPrimary)
                        .blur(radius: 2)

                    Text(card.cardData.description)
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                        .blur(radius: 2)
                }

                Spacer()

                Image(systemName: "lock.fill")
                    .foregroundColor(SupportTheme.Celebration.gold)
            }

            Divider()

            Button(action: onTap) {
                HStack {
                    Image(systemName: "star.fill")
                    Text("Upgrade to Unlock")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.supportPrimary)
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    VStack(spacing: SupportTheme.Spacing.m) {
        ExerciseActionCard(
            card: ActionCard(
                id: "1",
                sessionId: "s1",
                messageId: "m1",
                cardType: .exercise,
                cardData: ActionCard.CardData(
                    title: "Take a Deep Breath",
                    description: "A calming 4-7-8 breathing exercise",
                    icon: "wind",
                    estimatedMinutes: 3,
                    actionDestination: ActionCard.ActionDestination(type: "exercise", id: "breath-4-7-8", params: nil),
                    isPremium: false,
                    priority: 90,
                    conditions: nil
                ),
                isDismissed: false,
                isCompleted: false,
                displayedAt: Date(),
                actionTakenAt: nil,
                expiresAt: nil
            )
        )

        PremiumLockedCard(
            card: ActionCard(
                id: "2",
                sessionId: "s1",
                messageId: "m1",
                cardType: .exercise,
                cardData: ActionCard.CardData(
                    title: "Premium Meditation",
                    description: "Unlock this guided meditation",
                    icon: "crown",
                    estimatedMinutes: 10,
                    actionDestination: ActionCard.ActionDestination(type: "exercise", id: "premium-1", params: nil),
                    isPremium: true,
                    priority: 70,
                    conditions: nil
                ),
                isDismissed: false,
                isCompleted: false,
                displayedAt: Date(),
                actionTakenAt: nil,
                expiresAt: nil
            ),
            onTap: {}
        )
    }
    .padding()
}
