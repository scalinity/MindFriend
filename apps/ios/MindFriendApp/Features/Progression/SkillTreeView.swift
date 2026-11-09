import SwiftUI

/// Displays all skill progress in a tree-like view
struct SkillTreeView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var skills: [SkillProgress] = []
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        ScrollView {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Header
                headerSection

                // Skills list
                if isLoading {
                    ProgressView()
                        .padding(.top, SupportTheme.Spacing.xl)
                } else if let error {
                    SupportUnavailableState(title: "Skills couldn't load", message: error.localizedDescription,
                        actionTitle: "Try again", action: { Task { await loadSkills() } })
                } else if skills.isEmpty {
                    emptyState
                } else {
                    skillsList
                }
            }
            .padding(SupportTheme.Spacing.m)
        }
        .supportScreen()
        .foregroundStyle(SupportTheme.textPrimary)
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
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
            Text("Your skill progress")
                .font(.title2)
                .fontWeight(.bold).accessibilityAddTraits(.isHeader)

            Text("Complete exercises to level up each skill. Higher skill levels unlock advanced techniques.")
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var skillsList: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            ForEach(skills) { skill in
                SkillRow(skill: skill)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundColor(SupportTheme.textSecondary)

            Text("No skill progress yet")
                .font(.headline)

            Text("Complete exercises to start building your skills. Each exercise type has its own mastery track.")
                .font(.subheadline)
                .foregroundColor(SupportTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, SupportTheme.Spacing.xl)
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    // MARK: - Data Loading

    private func loadSkills() async {
        error = nil
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
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: SupportTheme.Spacing.s) {
            // Skill header
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: SupportTheme.Spacing.s))
                : AnyLayout(HStackLayout(alignment: .top, spacing: SupportTheme.Spacing.s))
            layout {
                // Icon
                ZStack {
                    Circle()
                        .fill(skillColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: skillIcon)
                        .font(.title3)
                        .foregroundColor(skillColor)
                }

                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                    Text(skill.skillType.displayName)
                        .font(.headline)

                    Text(skill.levelTitle)
                        .font(.subheadline)
                        .foregroundColor(SupportTheme.textSecondary)
                }

                if !typeSize.isAccessibilitySize { Spacer() }

                // Level badge
                VStack(alignment: .trailing, spacing: SupportTheme.Spacing.xxs) {
                    Text("Level \(skill.skillLevel)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(skillColor)

                    Text("\(skill.xp) XP")
                        .font(.caption)
                        .foregroundColor(SupportTheme.textSecondary)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(SupportTheme.separator)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                        .fill(
                            SupportTheme.accent
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
                        .foregroundColor(SupportTheme.textSecondary)
                } else {
                    Text("Highest level reached")
                        .font(.caption)
                        .foregroundColor(skillColor)
                }

                Spacer()

                Text("\(Int(progressPercentage * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(SupportTheme.textSecondary)
            }
        }
        .supportCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(skill.skillType.displayName), level \(skill.skillLevel), \(skill.levelTitle). \(skill.xp) XP total.")
    }

    // MARK: - Computed Properties

    private var skillIcon: String { skill.skillType.icon }
    private var skillColor: Color { SupportTheme.accent }

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
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: skillType.icon)
                .font(.caption)
                .foregroundColor(SupportTheme.accent)

            Text("Lvl \(level)")
                .font(.caption)
                .fontWeight(.medium)

            Text("•")
                .font(.caption2)
                .foregroundColor(SupportTheme.textSecondary)

            Text("\(xp) XP")
                .font(.caption)
                .foregroundColor(SupportTheme.textSecondary)
        }
        .padding(.horizontal, SupportTheme.Spacing.xs)
        .padding(.vertical, SupportTheme.Spacing.xxs)
        .background(SupportTheme.accent.opacity(0.1))
        .cornerRadius(SupportTheme.controlRadius)
    }
}

#Preview {
    NavigationStack {
        SkillTreeView()
            .environmentObject(DependencyContainer())
    }
}

#Preview("Skill Row") {
    VStack(spacing: SupportTheme.Spacing.m) {
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
    .padding(SupportTheme.Spacing.m)
}
