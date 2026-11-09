//
//  JourneyGetStartedStep.swift
//  MindFriendApp
//
//  Tutorial Step 4: Final CTA to start exploring journeys
//

import SwiftUI

/// Step 4: Encourage user to start their first journey
struct JourneyGetStartedStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var showSparkle = false
    @State private var showCards = false

    private let sampleJourneys = [
        ("Stress Relief", "brain.head.profile", SupportTheme.accent, "14 days"),
        ("Better Sleep", "moon.zzz.fill", SupportTheme.accent, "21 days"),
        ("Build Confidence", "figure.stand", SupportTheme.accent, "14 days")
    ]

    var body: some View {
        JourneyTutorialStepLayout(
            icon: "sparkles",
            iconColor: SupportTheme.accent,
            headline: "Choose Your Path",
            subheadline: "Browse our journeys and find one that speaks to where you are right now.",
            primaryLabel: "Explore Journeys",
            primaryAction: onComplete,
            skipAction: nil
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Sample journey cards
                VStack(spacing: SupportTheme.Spacing.xs) {
                    ForEach(Array(sampleJourneys.enumerated()), id: \.offset) { index, journey in
                        journeyPreviewCard(
                            title: journey.0,
                            icon: journey.1,
                            color: journey.2,
                            duration: journey.3,
                            index: index
                        )
                    }
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Tips
                HStack(spacing: SupportTheme.Spacing.s) {
                    tipItem(icon: "heart.fill", text: "Pick what resonates")
                    tipItem(icon: "clock.fill", text: "Start when ready")
                }
                .padding(.horizontal, SupportTheme.Spacing.m)

                // Encouragement
                HStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(SupportTheme.accent)
                        .scaleEffect(reduceMotion ? 1 : (showSparkle ? 1.2 : 1.0))

                    Text("Your transformation begins with a single step")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.horizontal, SupportTheme.Spacing.m)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCards = true
                }
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    showSparkle = true
                }
            }
        }
    }

    @ViewBuilder
    private func journeyPreviewCard(title: String, icon: String, color: Color, duration: String, index: Int) -> some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(SupportTheme.surface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Text(duration)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.s)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        .opacity(showCards ? 1 : 0)
        .offset(x: reduceMotion ? 0 : (showCards ? 0 : 30))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.4).delay(Double(index) * 0.1), value: showCards)
    }

    @ViewBuilder
    private func tipItem(icon: String, text: String) -> some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(SupportTheme.accent)

            Text(text)
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }
}

#Preview {
    JourneyGetStartedStep(onComplete: {})
}
