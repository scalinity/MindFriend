import SwiftUI

struct ActionCardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let card: ActionCard
    let onTap: () -> Void
    let onDismiss: () -> Void

    @State private var isPressed = false

    var body: some View {
        cardContent
        .opacity(isPressed ? 0.85 : 1)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            onDismiss()
        } onPressingChanged: { pressing in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.1)) {
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
            MoodActionCard(card: card, onMoodSelected: { _ in })
        case .resource:
            ResourceActionCard(card: card)
        case .chat:
            ChatSuggestionCard(card: card, onSuggestionSelected: { _ in })
        }
    }
}

struct ActionCardStackView: View {
    let cards: [ActionCard]
    let onCardTap: (ActionCard) -> Void
    let onCardDismiss: (ActionCard) -> Void

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            ForEach(cards) { card in
                ActionCardView(card: card, onTap: { onCardTap(card) }, onDismiss: { onCardDismiss(card) })
            }
        }
        .padding(.vertical, SupportTheme.Spacing.xs)
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
