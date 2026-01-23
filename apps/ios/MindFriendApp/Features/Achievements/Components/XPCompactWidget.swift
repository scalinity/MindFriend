// MindFriend XP Compact Widget
// Compact XP progress bar for HomeView

import SwiftUI

struct XPCompactWidget: View {
    @EnvironmentObject private var achievementService: AchievementService
    @Binding var selectedTab: Int // To navigate to achievements
    
    private var experience: UserExperience? {
        achievementService.userExperience
    }
    
    var body: some View {
        Button {
            selectedTab = 3 // Navigate to Achievements tab (index 3)
        } label: {
            HStack(spacing: 12) {
                // Level badge
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Text("\(experience?.currentLevel ?? 1)")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                }
                
                // Progress bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Level \(experience?.currentLevel ?? 1)")
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Text("\(experience?.xpToNextLevel ?? 100) XP to next")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: geometry.size.width * (experience?.progressToNextLevel ?? 0),
                                    height: 8
                                )
                                .animation(.spring(response: 0.4), value: experience?.totalXp)
                        }
                    }
                    .frame(height: 8)
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}
