import SwiftUI

struct ActionCardView: View {
    let card: ActionCard
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var isPressed = false
    @Environment(\.isPremium) private var isPremium

    var body: some View {
        Group {
            if card.cardData.isPremium && !isPremium {
                PremiumLockedCardView(card: card, onTap: onTap)
            } else {
                cardContent
            }
        }
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            onDismiss()
        } onPressingChanged: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }
    }

    @ViewBuilder
    private var cardContent: some View {
        switch card.cardType {
        case .exercise:
            ExerciseActionCard(card: card)
        case .journaling:
            JournalingActionCard(card: card)
        case .quest:
            QuestActionCard(card: card)
        case .mood:
            MoodActionCard(card: card)
        case .resource:
            ResourceActionCard(card: card)
        case .chat:
            ChatSuggestionCard(card: card)
        }
    }
}

struct ActionCardStackView: View {
    let cards: [ActionCard]
    let onCardTap: (ActionCard) -> Void
    let onCardDismiss: (ActionCard) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(cards) { card in
                ActionCardView(card: card, onTap: { onCardTap(card) }, onDismiss: { onCardDismiss(card) })
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    VStack {
        ActionCardView(
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
            ),
            onTap: {},
            onDismiss: {}
        )
    }
    .padding()
}
