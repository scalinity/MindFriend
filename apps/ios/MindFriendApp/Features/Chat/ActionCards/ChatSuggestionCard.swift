import SwiftUI

struct ChatSuggestionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let card: ActionCard
    let onSuggestionSelected: (String) -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
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
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.supportSecondary)
            }
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.08), radius: 8, x: 0, y: 2)
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
