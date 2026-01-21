import SwiftUI

struct MoodActionCard: View {
    let card: ActionCard
    let onMoodSelected: (String) -> Void

    private let moodEmojis = ["😊", "🙂", "😐", "😔", "😢"]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: card.cardData.icon)
                        .font(.system(size: 20))
                        .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(card.cardData.title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(card.cardData.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 16) {
                ForEach(moodEmojis, id: \.self) { emoji in
                    Button {
                        onMoodSelected(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                    }
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    MoodActionCard(
        card: ActionCard(
            id: "1",
            sessionId: "s1",
            messageId: "m1",
            cardType: .mood,
            cardData: ActionCard.CardData(
                title: "How Are You Feeling?",
                description: "Take a moment to check in with yourself",
                icon: "face.smiling",
                estimatedMinutes: 1,
                actionDestination: ActionCard.ActionDestination(type: "mood", id: nil, params: nil),
                isPremium: false,
                priority: 95,
                conditions: nil
            ),
            isDismissed: false,
            isCompleted: false,
            displayedAt: Date(),
            actionTakenAt: nil,
            expiresAt: nil
        ),
        onMoodSelected: { _ in }
    )
    .padding()
}
