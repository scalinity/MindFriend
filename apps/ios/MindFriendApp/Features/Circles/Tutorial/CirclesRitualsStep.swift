//
//  CirclesRitualsStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Group rituals and activities
//

import SwiftUI

/// Step 3: Show group rituals and support features
struct CirclesRitualsStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var showRituals = false

    private let rituals: [(icon: String, color: Color, name: String, description: String)] = [
        ("sunrise.fill", SupportTheme.Area.quests.palette.ink, "Morning Intentions", "Start the day together with shared goals"),
        ("moon.stars.fill", SupportTheme.Area.journal.palette.ink, "Evening Reflection", "Wind down and share gratitude"),
        ("figure.mind.and.body", SupportTheme.Status.positive, "Group Exercise", "Do wellness exercises together")
    ]

    var body: some View {
        TutorialStepView(
            icon: "sparkles",
            iconColor: SupportTheme.Area.journal.palette.ink,
            headline: "Rituals & Support",
            subheadline: "Join scheduled group activities and support each other's growth.",
            primaryLabel: "Explore Circles",
            primaryAction: onComplete
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(Array(rituals.enumerated()), id: \.element.name) { index, ritual in
                    HStack(spacing: SupportTheme.Spacing.s) {
                        ZStack {
                            Circle()
                                .fill(ritual.color.opacity(0.15))
                                .frame(width: 38, height: 38)
                            Image(systemName: ritual.icon)
                                .foregroundStyle(ritual.color)
                        }

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(ritual.name)
                                .font(.subheadline.weight(.medium))
                            Text(ritual.description)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .opacity(showRituals ? 1 : 0)
                    .offset(x: reduceMotion ? 0 : (showRituals ? 0 : 20))
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3).delay(0.3 + Double(index) * 0.15),
                        value: showRituals
                    )
                }

                // Invite prompt
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "person.badge.plus")
                        .foregroundStyle(SupportTheme.Area.people.palette.ink)
                    Text("Invite friends to create your first circle")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .padding(.top, SupportTheme.Spacing.xs)
                .opacity(showRituals ? 1 : 0)
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
            .onAppear { showRituals = true }
        }
    }
}

#Preview {
    CirclesRitualsStep(onComplete: {})
}
