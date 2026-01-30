import SwiftUI

/// Displays all skill progress in a tree-like view
struct SkillTreeView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var skills: [SkillProgress] = []
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                headerSection

                // Skills list
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else if skills.isEmpty {
                    emptyState
                } else {
                    skillsList
                }
            }
            .padding()
        }
        .navigationTitle("Skills")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await loadSkills()
        }
        .refreshable {
            await loadSkills()
        }
        .skillLevelUpCelebration()
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Mastery Progress")
                .font(.title2)
                .fontWeight(.bold)

            Text("Complete exercises to level up each skill. Higher skill levels unlock advanced techniques.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var skillsList: some View {
        VStack(spacing: 12) {
            ForEach(skills) { skill in
                SkillRow(skill: skill)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Skill Progress Yet")
                .font(.headline)

            Text("Complete exercises to start building your skills. Each exercise type has its own mastery track.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal)
    }

    // MARK: - Data Loading

    private func loadSkills() async {
        do {
            skills = try await container.supabaseDataService.getSkillProgress()
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
}

/// Individual skill row with progress visualization
struct SkillRow: View {
    let skill: SkillProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Skill header
            HStack {
                // Icon
                ZStack {
                    Circle()
                        .fill(skillColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: skillIcon)
                        .font(.title3)
                        .foregroundColor(skillColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.skillType.displayName)
                        .font(.headline)

                    Text(skill.levelTitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Level badge
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Level \(skill.skillLevel)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(skillColor)

                    Text("\(skill.xp) XP")
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
                                colors: [skillColor, skillColor.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * progressPercentage, height: 8)
                }
            }
            .frame(height: 8)

            // Progress text
            HStack {
                if skill.skillLevel < 5 {
                    Text("\(xpToNextLevel) XP to next level")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Max level reached!")
                        .font(.caption)
                        .foregroundColor(skillColor)
                }

                Spacer()

                Text("\(Int(progressPercentage * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(skill.skillType.displayName), level \(skill.skillLevel), \(skill.levelTitle). \(skill.xp) XP total.")
    }

    // MARK: - Computed Properties

    private var skillIcon: String { skill.skillType.icon }
    private var skillColor: Color { skill.skillType.themeColor }

    private var progressPercentage: Double {
        let thresholds = SkillLevel.thresholds
        let currentLevel = skill.skillLevel
        guard currentLevel < 5 else { return 1.0 }

        let currentThreshold = thresholds[currentLevel]
        let nextThreshold = thresholds[currentLevel + 1]
        let xpInLevel = skill.xp - currentThreshold
        let xpNeeded = nextThreshold - currentThreshold

        return min(1.0, Double(xpInLevel) / Double(xpNeeded))
    }

    private var xpToNextLevel: Int {
        let thresholds = SkillLevel.thresholds
        let currentLevel = skill.skillLevel
        guard currentLevel < 5 else { return 0 }

        let nextThreshold = thresholds[currentLevel + 1]
        return max(0, nextThreshold - skill.xp)
    }
}

/// Compact skill indicator for exercise list header
struct SkillIndicatorView: View {
    let skillType: ExerciseType
    let level: Int
    let xp: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: skillType.icon)
                .font(.caption)
                .foregroundColor(skillType.themeColor)

            Text("Lvl \(level)")
                .font(.caption)
                .fontWeight(.medium)

            Text("•")
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("\(xp) XP")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(skillType.themeColor.opacity(0.1))
        .cornerRadius(12)
    }
}

#Preview {
    NavigationStack {
        SkillTreeView()
            .environmentObject(DependencyContainer())
    }
}

#Preview("Skill Row") {
    VStack(spacing: 16) {
        SkillRow(skill: SkillProgress(
            id: "1",
            userId: "u1",
            skillType: .breathing,
            xp: 320,
            skillLevel: 2,
            createdAt: Date(),
            updatedAt: Date()
        ))

        SkillRow(skill: SkillProgress(
            id: "2",
            userId: "u1",
            skillType: .meditation,
            xp: 1500,
            skillLevel: 3,
            createdAt: Date(),
            updatedAt: Date()
        ))

        SkillRow(skill: SkillProgress(
            id: "3",
            userId: "u1",
            skillType: .movement,
            xp: 7500,
            skillLevel: 5,
            createdAt: Date(),
            updatedAt: Date()
        ))

        SkillIndicatorView(skillType: .breathing, level: 2, xp: 320)
    }
    .padding()
}
