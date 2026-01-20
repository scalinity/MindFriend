import SwiftUI

/// Displays the user's current level and XP progress
struct LevelProgressView: View {
    let userLevel: UserLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Level badge - matches Achievements page design
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 56, height: 56)

                    Text("\(userLevel.level)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Level \(userLevel.level)")
                        .font(.headline)
                    Text(userLevel.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(userLevel.currentXP) XP")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                    Text("this week: \(userLevel.xpThisWeek)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * userLevel.progress, height: 8)
                }
            }
            .frame(height: 8)

            // XP to next level
            if userLevel.level < 50 {
                Text("\(userLevel.xpToNextLevel) XP to next level")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Max level reached!")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(userLevel.level), \(userLevel.title). \(userLevel.currentXP) XP total. \(userLevel.xpToNextLevel) XP to next level.")
    }
}

/// Compact version for smaller spaces
struct LevelBadgeView: View {
    let level: Int
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)

                Text("\(level)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        LevelProgressView(userLevel: UserLevel(
            level: 12,
            title: "Explorer",
            currentXP: 3850,
            nextLevelXP: 4500,
            xpThisWeek: 180
        ))

        LevelProgressView(userLevel: UserLevel(
            level: 50,
            title: "Transcendent",
            currentXP: 65000,
            nextLevelXP: 63700,
            xpThisWeek: 450
        ))

        LevelBadgeView(level: 12, title: "Explorer")
    }
    .padding()
}
