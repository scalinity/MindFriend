import SwiftUI

/// Card showing what activity happened while user was away
/// Displays hugs received, circle posts, and friend milestones
struct WhatYouMissedCard: View {
    let summary: AbsenceSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                Text("While you were away...")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            // Activity items
            VStack(spacing: 12) {
                // Hugs received
                if summary.hugsReceived > 0 {
                    activityRow(
                        icon: "heart.fill",
                        iconColor: .pink,
                        text: hugText
                    )
                }

                // Circle posts
                if summary.circlePosts > 0 {
                    activityRow(
                        icon: "bubble.left.and.bubble.right.fill",
                        iconColor: .blue,
                        text: postsText
                    )
                }

                // Friend milestones
                ForEach(summary.friendMilestones.prefix(3)) { milestone in
                    activityRow(
                        icon: milestone.isStreak ? "flame.fill" : "star.fill",
                        iconColor: milestone.isStreak ? .orange : .yellow,
                        text: "\(milestone.name) hit a milestone: \(milestone.milestone)"
                    )
                }
            }

            // Encouraging footer
            if summary.hasActivity {
                Text("Your community is here for you! 💛")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Components

    private func activityRow(icon: String, iconColor: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()
        }
    }

    // MARK: - Text Helpers

    private var hugText: String {
        if summary.hugsReceived == 1 {
            return "Someone sent you a hug!"
        } else {
            return "\(summary.hugsReceived) people sent you hugs!"
        }
    }

    private var postsText: String {
        if summary.circlePosts == 1 {
            return "1 new post in your circles"
        } else {
            return "\(summary.circlePosts) new posts in your circles"
        }
    }
}

// MARK: - Preview

#Preview("With Activity") {
    WhatYouMissedCard(
        summary: AbsenceSummary(
            absenceDays: 7,
            lapseTier: .extendedBreak,
            hugsReceived: 5,
            circlePosts: 12,
            friendMilestones: [
                .init(name: "Sarah", milestone: "7-day streak!", isStreak: true),
                .init(name: "Mike", milestone: "First journal entry", isStreak: false)
            ]
        )
    )
    .padding()
}

#Preview("Minimal Activity") {
    WhatYouMissedCard(
        summary: AbsenceSummary(
            absenceDays: 3,
            lapseTier: .briefBreak,
            hugsReceived: 1,
            circlePosts: 0,
            friendMilestones: []
        )
    )
    .padding()
}
