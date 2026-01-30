//
//  HomeWelcomeStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Welcome to your wellness hub
//

import SwiftUI

/// Step 1: Welcome and introduce the home screen concept
struct HomeWelcomeStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showCards = false

    var body: some View {
        TutorialStepView(
            icon: "house.fill",
            iconColor: .indigo,
            headline: "Welcome to Your Home",
            subheadline: "This is your personal wellness hub. Everything you need is right here.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 8) {
                // Animated card previews
                VStack(spacing: 8) {
                    ForEach(Array(homeFeatures.enumerated()), id: \.element.title) { index, feature in
                        HStack(spacing: 12) {
                            Image(systemName: feature.icon)
                                .font(.title3)
                                .foregroundStyle(feature.color)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(.subheadline.weight(.medium))
                                Text(feature.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .opacity(showCards ? 1 : 0)
                        .offset(y: showCards ? 0 : 10)
                        .animation(
                            .easeOut(duration: 0.4).delay(0.2 + Double(index) * 0.15),
                            value: showCards
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            .onAppear {
                showCards = true
            }
        }
    }

    private var homeFeatures: [(icon: String, color: Color, title: String, description: String)] {
        [
            ("star.fill", .orange, "Daily Quest", "Your personalized daily challenge"),
            ("chart.line.uptrend.xyaxis", .green, "Your Progress", "Track streaks and achievements"),
            ("face.smiling", .pink, "Mood Check-in", "Log how you're feeling"),
            ("sparkles", .purple, "AI Insights", "Personalized recommendations")
        ]
    }
}

#Preview {
    HomeWelcomeStep(onNext: {}, onSkip: {})
}
