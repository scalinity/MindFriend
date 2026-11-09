//
//  JourneyProgressStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Explains how daily progress works
//

import SwiftUI

/// Step 2: Explain how completing quests advances the journey
struct JourneyProgressStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var currentDay = 1
    @State private var showProgress = false

    var body: some View {
        JourneyTutorialStepLayout(
            icon: "calendar.badge.checkmark",
            iconColor: SupportTheme.accent,
            headline: "One Day at a Time",
            subheadline: "Complete your daily quest to advance through your journey.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Animated day progression
                HStack(spacing: SupportTheme.Spacing.s) {
                    ForEach(1...5, id: \.self) { day in
                        dayIndicator(day: day)
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Progress explanation
                VStack(spacing: SupportTheme.Spacing.xs) {
                    progressRow(
                        icon: "checkmark.circle.fill",
                        color: SupportTheme.accent,
                        text: "Complete today's quest"
                    )

                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    progressRow(
                        icon: "arrow.right.circle.fill",
                        color: SupportTheme.accent,
                        text: "Journey advances to next day"
                    )

                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    progressRow(
                        icon: "sparkles",
                        color: SupportTheme.accent,
                        text: "Skills build over time"
                    )
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Note
                Text("**No pressure** - your journey waits for you. Complete at your own pace.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showProgress = true
                }
                // Animate through days
                animateDays()
            }
        }
    }

    @ViewBuilder
    private func dayIndicator(day: Int) -> some View {
        let isCompleted = day < currentDay
        let isCurrent = day == currentDay
        let isUpcoming = day > currentDay

        VStack(spacing: SupportTheme.Spacing.xxs) {
            ZStack {
                Circle()
                    .fill(isCompleted ? SupportTheme.accent : isCurrent ? SupportTheme.accent : SupportTheme.separator)
                    .frame(width: 36, height: 36)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(SupportTheme.textPrimary)
                } else {
                    Text("\(day)")
                        .font(.caption.bold())
                        .foregroundStyle(isCurrent ? SupportTheme.onAccent : SupportTheme.textSecondary)
                }
            }
            .scaleEffect(reduceMotion ? 1 : (isCurrent ? 1.1 : 1.0))
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3), value: currentDay)

            Text("Day \(day)")
                .font(.caption2)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func progressRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textPrimary)

            Spacer()
        }
        .opacity(showProgress ? 1 : 0)
        .offset(x: reduceMotion ? 0 : (showProgress ? 0 : -20))
    }

    private func animateDays() {
        // Animate through first 3 days
        for i in 2...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i - 1) * 0.8) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.4)) {
                    currentDay = i
                }
            }
        }
    }
}

#Preview {
    JourneyProgressStep(onNext: {}, onSkip: {})
}
