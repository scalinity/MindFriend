import SwiftUI

struct QuestActionCard: View {
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

#Preview {
    QuestActionCard(
        card: ActionCard(
            id: "1",
            sessionId: "s1",
            messageId: "m1",
            cardType: .quest,
            cardData: ActionCard.CardData(
                title: "Daily Quest Available",
                description: "Make time for a small step toward your wellbeing",
                icon: "star",
                estimatedMinutes: 15,
                actionDestination: ActionCard.ActionDestination(type: "quest", id: nil, params: nil),
                isPremium: false,
                priority: 75,
                conditions: nil
            ),
            isDismissed: false,
            isCompleted: false,
            displayedAt: Date(),
            actionTakenAt: nil,
            expiresAt: nil
        )
    )
    .padding()
}
