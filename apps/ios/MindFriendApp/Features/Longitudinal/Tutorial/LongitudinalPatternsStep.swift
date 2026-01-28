//
//  LongitudinalPatternsStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: AI pattern recognition
//

import SwiftUI

/// Step 2: Show how AI finds long-term patterns
struct LongitudinalPatternsStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showPatterns = false

    private let patterns: [(icon: String, color: Color, title: String, insight: String)] = [
        ("sun.max.fill", .orange, "Seasonal Impact", "Your mood tends to dip in winter months"),
        ("moon.stars.fill", .purple, "Sleep Correlation", "Better sleep weeks correlate with higher mood"),
        ("figure.walk", .green, "Exercise Pattern", "Active months show 20% higher wellbeing scores")
    ]

    var body: some View {
        TutorialStepView(
            icon: "brain.head.profile",
            iconColor: .purple,
            headline: "Pattern Recognition",
            subheadline: "AI analyzes months of data to find meaningful patterns in your wellbeing.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 12) {
                ForEach(Array(patterns.enumerated()), id: \.element.title) { index, pattern in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: pattern.icon)
                            .font(.title3)
                            .foregroundStyle(pattern.color)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(pattern.title)
                                .font(.subheadline.weight(.medium))
                            Text(pattern.insight)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(pattern.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showPatterns ? 1 : 0)
                    .offset(y: showPatterns ? 0 : 15)
                    .animation(
                        .easeOut(duration: 0.4).delay(0.3 + Double(index) * 0.15),
                        value: showPatterns
                    )
                }

                // Note
                Text("Patterns become more accurate as you log more data")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .opacity(showPatterns ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .onAppear { showPatterns = true }
        }
    }
}

#Preview {
    LongitudinalPatternsStep(onNext: {}, onSkip: {})
}
