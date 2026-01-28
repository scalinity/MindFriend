//
//  JourneyGetStartedStep.swift
//  MindFriendApp
//
//  Tutorial Step 4: Final CTA to start exploring journeys
//

import SwiftUI

/// Step 4: Encourage user to start their first journey
struct JourneyGetStartedStep: View {
    let onComplete: () -> Void

    @State private var showSparkle = false
    @State private var showCards = false

    private let sampleJourneys = [
        ("Stress Relief", "brain.head.profile", Color.blue, "14 days"),
        ("Better Sleep", "moon.zzz.fill", Color.indigo, "21 days"),
        ("Build Confidence", "figure.stand", Color.purple, "14 days")
    ]

    var body: some View {
        JourneyTutorialStepLayout(
            icon: "sparkles",
            iconColor: .purple,
            headline: "Choose Your Path",
            subheadline: "Browse our journeys and find one that speaks to where you are right now.",
            primaryLabel: "Explore Journeys",
            primaryAction: onComplete,
            skipAction: nil
        ) {
            VStack(spacing: 20) {
                // Sample journey cards
                VStack(spacing: 12) {
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
                .padding(.horizontal, 24)

                // Tips
                HStack(spacing: 16) {
                    tipItem(icon: "heart.fill", text: "Pick what resonates")
                    tipItem(icon: "clock.fill", text: "Start when ready")
                }
                .padding(.horizontal, 24)

                // Encouragement
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.yellow)
                        .scaleEffect(showSparkle ? 1.2 : 1.0)

                    Text("Your transformation begins with a single step")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
            }
            .onAppear {
                withAnimation {
                    showCards = true
                }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    showSparkle = true
                }
            }
        }
    }

    @ViewBuilder
    private func journeyPreviewCard(title: String, icon: String, color: Color, duration: String, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Text(duration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(showCards ? 1 : 0)
        .offset(x: showCards ? 0 : 30)
        .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.1), value: showCards)
    }

    @ViewBuilder
    private func tipItem(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    JourneyGetStartedStep(onComplete: {})
}
