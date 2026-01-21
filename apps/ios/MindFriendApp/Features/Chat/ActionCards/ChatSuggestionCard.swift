import SwiftUI

struct ChatSuggestionCard: View {
    let card: ActionCard
    let onSuggestionSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
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
                }

                Spacer()
            }

            if let suggestion = card.cardData.actionDestination.params?["suggestion"] {
                Button {
                    onSuggestionSelected(suggestion)
                } label: {
                    HStack {
                        Image(systemName: "arrowshape.turn.up.left")
                        Text(suggestion)
                            .lineLimit(2)
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
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
    ChatSuggestionCard(
        card: ActionCard(
            id: "1",
            sessionId: "s1",
            messageId: "m1",
            cardType: .chat,
            cardData: ActionCard.CardData(
                title: "Keep the Conversation Going",
                description: "Here's a suggestion for your response",
                icon: "bubble.left.and.bubble.right",
                estimatedMinutes: 1,
                actionDestination: ActionCard.ActionDestination(
                    type: "chat",
                    id: nil,
                    params: ["suggestion": "Tell me more about that."]
                ),
                isPremium: false,
                priority: 60,
                conditions: nil
            ),
            isDismissed: false,
            isCompleted: false,
            displayedAt: Date(),
            actionTakenAt: nil,
            expiresAt: nil
        ),
        onSuggestionSelected: { _ in }
    )
    .padding()
}
