//
//  ProgramsProgressStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Daily progress and streaks
//

import SwiftUI

/// Step 3: Show how daily program progress works
struct ProgramsProgressStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var currentDay = 0
    @State private var progress: Double = 0
    @State private var showFeatures = false

    var body: some View {
        TutorialStepView(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: SupportTheme.accent,
            headline: "Track Your Progress",
            subheadline: "Complete each day's content to advance through the program and build momentum.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Progress visualization
                VStack(spacing: SupportTheme.Spacing.xs) {
                    // Day indicator
                    HStack {
                        Text("Day \(currentDay) of 21")
                            .font(.headline)
                            .contentTransition(reduceMotion ? .opacity : .numericText())

                        Spacer()


                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(SupportTheme.separator)

                            RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                                .fill(SupportTheme.accent)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 12)

                    // Day circles
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        ForEach(1...7, id: \.self) { day in
                            Circle()
                                .fill(day <= currentDay ? SupportTheme.accent : SupportTheme.separator)
                                .frame(width: 24, height: 24)
                                .overlay {
                                    if day <= currentDay {
                                        Image(systemName: "checkmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(SupportTheme.textPrimary)
                                    } else {
                                        Text("\(day)")
                                            .font(.caption2)
                                            .foregroundStyle(SupportTheme.textSecondary)
                                    }
                                }
                        }
                        Text("...")
                            .foregroundStyle(SupportTheme.textSecondary)
                    }
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Features
                VStack(spacing: SupportTheme.Spacing.xs) {
                    ProgressFeature(icon: "bell.fill", text: "Daily reminders keep you on track")
                    ProgressFeature(icon: "arrow.uturn.backward", text: "Review past days anytime")
                    ProgressFeature(icon: "pause.circle.fill", text: "Pause without losing progress")
                }
                .padding(.horizontal, SupportTheme.Spacing.l)
                .opacity(showFeatures ? 1 : 0)
            }
            .onAppear {
                animateProgress()
            }
        }
    }

    private func animateProgress() {
        for day in 1...7 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(day) * 0.2) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.7)) {
                    currentDay = day
                    progress = Double(day) / 21.0
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showFeatures = true
            }
        }
    }
}

// MARK: - Progress Feature Row

private struct ProgressFeature: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(SupportTheme.accent)
                .frame(minWidth: 20)

            Text(text)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
    }
}

#Preview {
    ProgramsProgressStep(onNext: {}, onSkip: {})
}
