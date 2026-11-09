import SwiftUI

struct MoodActionCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let card: ActionCard
    let onMoodSelected: (String) -> Void

    private let moodEmojis = ["😊", "🙂", "😐", "😔", "😢"]

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

            HStack(spacing: SupportTheme.Spacing.m) {
                ForEach(moodEmojis, id: \.self) { emoji in
                    Button {
                        onMoodSelected(emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                    }
                    .frame(width: 44, height: 44)
                    .background(SupportTheme.surface)
                    .clipShape(Circle())
                }
            }
        }
        .supportCard()
        .shadow(color: SupportTheme.canvas.opacity(0.08), radius: 8, x: 0, y: 2)
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
