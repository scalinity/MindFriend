//
//  AchievementsSkillsStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Skill trees
//

import SwiftUI

/// Step 3: Show skill progression system
struct AchievementsSkillsStep: View {
    let onComplete: () -> Void

    @State private var showSkills = false

    private let skills: [(icon: String, color: Color, name: String, level: Int, maxLevel: Int)] = [
        ("wind", .cyan, "Breathing", 3, 5),
        ("sparkles", .purple, "Meditation", 2, 5),
        ("hand.raised.fill", .green, "Grounding", 1, 5),
        ("figure.walk", .orange, "Movement", 4, 5)
    ]

    var body: some View {
        TutorialStepView(
            icon: "chart.bar.xaxis.ascending",
            iconColor: .teal,
            headline: "Track Your Skills",
            subheadline: "Build mastery in different wellness areas. Each practice levels up your skills.",
            primaryLabel: "View Achievements",
            primaryAction: onComplete
        ) {
            VStack(spacing: 12) {
                ForEach(Array(skills.enumerated()), id: \.element.name) { index, skill in
                    HStack(spacing: 12) {
                        // Icon
                        ZStack {
                            Circle()
                                .fill(skill.color.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: skill.icon)
                                .foregroundStyle(skill.color)
                        }

                        // Info
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(skill.name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("Level \(skill.level)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            // Progress dots
                            HStack(spacing: 4) {
                                ForEach(1...skill.maxLevel, id: \.self) { level in
                                    Circle()
                                        .fill(level <= skill.level ? skill.color : Color(.systemGray5))
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showSkills ? 1 : 0)
                    .offset(x: showSkills ? 0 : 20)
                    .animation(
                        .easeOut(duration: 0.3).delay(0.3 + Double(index) * 0.1),
                        value: showSkills
                    )
                }

                // Explanation
                Text("Complete exercises to level up the corresponding skill tree")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .opacity(showSkills ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .onAppear { showSkills = true }
        }
    }
}

#Preview {
    AchievementsSkillsStep(onComplete: {})
}
