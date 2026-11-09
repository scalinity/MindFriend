//
//  AchievementsSkillsStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Skill trees
//

import SwiftUI

/// Step 3: Show skill progression system
struct AchievementsSkillsStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var showSkills = false

    private let skills: [(icon: String, color: Color, name: String, level: Int, maxLevel: Int)] = [
        ("wind", SupportTheme.accent, "Breathing", 3, 5),
        ("sparkles", SupportTheme.accent, "Meditation", 2, 5),
        ("hand.raised.fill", SupportTheme.accent, "Grounding", 1, 5),
        ("figure.walk", SupportTheme.accent, "Movement", 4, 5),
    ]

    var body: some View {
        TutorialStepView(
            icon: "chart.bar.xaxis.ascending",
            iconColor: SupportTheme.accent,
            headline: "Track Your Skills",
            subheadline: "Build mastery in different wellness areas. Each practice levels up your skills.",
            primaryLabel: "View Achievements",
            primaryAction: onComplete
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(Array(skills.enumerated()), id: \.element.name) { index, skill in
                    HStack(spacing: SupportTheme.Spacing.s) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(skill.color.opacity(0.15))
                                .frame(width: 38, height: 38)
                            Image(systemName: skill.icon)
                                .foregroundStyle(skill.color)
                        }

                        // Info
                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            HStack {
                                Text(skill.name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("Level \(skill.level)")
                                    .font(.caption)
                                    .foregroundStyle(SupportTheme.textSecondary)
                            }

                            // Progress dots
                            HStack(spacing: SupportTheme.Spacing.xxs) {
                                ForEach(1...skill.maxLevel, id: \.self) { level in
                                    Circle()
                                        .fill(level <= skill.level ? skill.color : SupportTheme.field)
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                    .opacity(showSkills ? 1 : 0)
                    .offset(x: reduceMotion ? 0 : (showSkills ? 0 : 20))
                    .animation(
                        reduceMotion
                            ? .easeInOut(duration: 0.2) : (.easeOut(duration: 0.3).delay(0.3 + Double(index) * 0.1)),
                        value: showSkills
                    )
                }

                // Explanation
                Text("Complete exercises to level up the corresponding skill tree")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .padding(.top, SupportTheme.Spacing.xs)
                    .opacity(showSkills ? 1 : 0)
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
            .onAppear { showSkills = true }
        }
    }
}

#Preview {
    AchievementsSkillsStep(onComplete: {})
}
