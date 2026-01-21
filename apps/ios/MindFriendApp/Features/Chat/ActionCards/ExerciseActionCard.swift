import SwiftUI

struct ExerciseActionCard: View {
    let card: ActionCard

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 48, height: 48)
                Image(systemName: card.cardData.icon)
                    .font(.system(size: 20))
                    .foregroundColor(.blue)
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

struct PremiumLockedCard: View {
    let card: ActionCard
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: card.cardData.icon)
                        .font(.system(size: 20))
                        .foregroundColor(.gray)
                        .blur(radius: 3)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.cardData.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .blur(radius: 2)

                    Text(card.cardData.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .blur(radius: 2)
                }

                Spacer()

                Image(systemName: "lock.fill")
                    .foregroundColor(.yellow)
            }

            Divider()

            Button(action: onTap) {
                HStack {
                    Image(systemName: "star.fill")
                    Text("Upgrade to Unlock")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    VStack(spacing: 16) {
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
