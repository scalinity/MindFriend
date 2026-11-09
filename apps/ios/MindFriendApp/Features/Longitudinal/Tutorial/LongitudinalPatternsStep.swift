//
//  LongitudinalPatternsStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: AI pattern recognition
//

import SwiftUI

/// Step 2: Show how AI finds long-term patterns
struct LongitudinalPatternsStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showPatterns = false

    private let patterns: [(icon: String, color: Color, title: String, insight: String)] = [
        ("sun.max.fill", SupportTheme.accent, "Seasonal Impact", "Your mood tends to dip in winter months"),
        ("moon.stars.fill", SupportTheme.accent, "Sleep Correlation", "Better sleep weeks correlate with higher mood"),
        ("figure.walk", SupportTheme.accent, "Exercise Pattern", "Active months show 20% higher wellbeing scores"),
    ]

    var body: some View {
        TutorialStepView(
            icon: "brain.head.profile",
            iconColor: SupportTheme.accent,
            headline: "Pattern Recognition",
            subheadline: "AI analyzes months of data to find meaningful patterns in your wellbeing.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(Array(patterns.enumerated()), id: \.element.title) { index, pattern in
                    HStack(alignment: .top, spacing: SupportTheme.Spacing.s) {
                        Image(systemName: pattern.icon)
                            .font(.title3)
                            .foregroundStyle(pattern.color)
                            .frame(minWidth: 28)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text(pattern.title)
                                .font(.subheadline.weight(.medium))
                            Text(pattern.insight)
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(pattern.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.cardRadius))
                    .opacity(showPatterns ? 1 : 0)
                    .offset(y: reduceMotion ? 0 : (showPatterns ? 0 : 15))
                    .animation(
                        reduceMotion
                            ? .easeInOut(duration: 0.2) : (.easeOut(duration: 0.4).delay(0.3 + Double(index) * 0.15)),
                        value: showPatterns
                    )
                }

                // Note
                Text("Patterns become more accurate as you log more data")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .padding(.top, SupportTheme.Spacing.xs)
                    .opacity(showPatterns ? 1 : 0)
            }
            .padding(.horizontal, SupportTheme.Spacing.l)
            .onAppear { showPatterns = true }
        }
    }
}

#Preview {
    LongitudinalPatternsStep(onNext: {}, onSkip: {})
}
