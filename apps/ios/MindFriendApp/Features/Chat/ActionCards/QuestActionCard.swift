import SwiftUI

struct QuestActionCard: View {
    let card: ActionCard

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: card.cardData.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.orange)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(card.cardData.title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(card.cardData.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label("\(card.cardData.estimatedMinutes) min", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
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
                description: "Complete this quest to earn XP and streak points",
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
