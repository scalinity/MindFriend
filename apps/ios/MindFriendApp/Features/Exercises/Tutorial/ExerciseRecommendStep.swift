//
//  ExerciseRecommendStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Explain personalized recommendations
//

import SwiftUI

/// Step 2: Show how recommendations adapt to your state
struct ExerciseRecommendStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var capacityLevel = 1
    @State private var showExplanation = false

    var body: some View {
        TutorialStepView(
            icon: "sparkles",
            iconColor: SupportTheme.Area.journal.palette.ink,
            headline: "Personalized For You",
            subheadline: "We recommend exercises based on your current energy and mood.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Capacity indicator
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text("Your Current Capacity")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        ForEach(1...5, id: \.self) { level in
                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(level <= capacityLevel ? capacityColor : SupportTheme.separator)
                                .frame(width: 36, height: 8)
                        }
                    }

                    Text(capacityLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(capacityColor)
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Explanation
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("How it works:")
                        .font(.subheadline.weight(.medium))

                    VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                        InfoPoint(text: "Low capacity? Quick, simple exercises")
                        InfoPoint(text: "Feeling good? Try longer, deeper practices")
                        InfoPoint(text: "Updates based on your mood check-ins")
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .padding(.horizontal, SupportTheme.Spacing.m)
                .opacity(showExplanation ? 1 : 0)
            }
            .onAppear {
                animateCapacity()
            }
        }
    }

    private var capacityColor: Color {
        switch capacityLevel {
        case 1: return .red
        case 2: return SupportTheme.Status.caution
        case 3: return SupportTheme.Area.exercises.palette.ink
        case 4: return SupportTheme.Status.positive
        case 5: return SupportTheme.Area.voice.palette.ink
        default: return SupportTheme.Area.voice.palette.ink
        }
    }

    private var capacityLabel: String {
        switch capacityLevel {
        case 1: return "Very Low"
        case 2: return "Low"
        case 3: return "Moderate"
        case 4: return "Good"
        case 5: return "High"
        default: return "Unknown"
        }
    }

    private func animateCapacity() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.7)) {
                capacityLevel += 1
            }
            if capacityLevel >= 4 {
                timer.invalidate()
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.3)) {
                    showExplanation = true
                }
            }
        }
    }
}

private struct InfoPoint: View {
    let text: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(SupportTheme.Status.positive)
            Text(text)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ExerciseRecommendStep(onNext: {}, onSkip: {})
}
