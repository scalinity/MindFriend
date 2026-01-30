//
//  HomeExploreStep.swift
//  MindFriendApp
//
//  Tutorial Step 4: Show how to explore features
//

import SwiftUI

/// Feature destination for navigation
enum ExploreFeatureDestination {
    case chat
    case exercises
    case circles
    case insights
    case achievements

    var targetTab: MainTab {
        switch self {
        case .chat: return .chat
        case .exercises: return .programs
        case .circles: return .circles
        case .insights: return .home
        case .achievements: return .profile
        }
    }
}

/// Step 4: Guide users to explore the app's features
struct HomeExploreStep: View {
    let onComplete: () -> Void
    let onNavigate: ((ExploreFeatureDestination) -> Void)?

    @State private var visibleFeatures: Set<String> = []

    init(onComplete: @escaping () -> Void, onNavigate: ((ExploreFeatureDestination) -> Void)? = nil) {
        self.onComplete = onComplete
        self.onNavigate = onNavigate
    }

    var body: some View {
        TutorialStepView(
            icon: "sparkles",
            iconColor: .purple,
            headline: "Explore & Discover",
            subheadline: "Your home screen adapts to your needs. Here's what you can access:",
            primaryLabel: "Get Started",
            primaryAction: onComplete
        ) {
            VStack(spacing: 6) {
                ForEach(Array(features.enumerated()), id: \.element.title) { index, feature in
                    Button {
                        onNavigate?(feature.destination)
                        onComplete()
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(feature.color.opacity(0.15))
                                    .frame(width: 32, height: 32)

                                Image(systemName: feature.icon)
                                    .font(.callout)
                                    .foregroundStyle(feature.color)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(feature.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(feature.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.secondarySystemBackground).opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .opacity(visibleFeatures.contains(feature.title) ? 1 : 0)
                    .offset(x: visibleFeatures.contains(feature.title) ? 0 : 20)
                }
            }
            .padding(.horizontal, 20)
            .onAppear {
                animateFeatures()
            }
        }
    }

    private var features: [(icon: String, color: Color, title: String, description: String, destination: ExploreFeatureDestination)] {
        [
            ("bubble.left.and.bubble.right.fill", .blue, "AI Chat", "Talk to your supportive companion", .chat),
            ("figure.mind.and.body", .green, "Exercises", "Breathing, meditation & more", .exercises),
            ("person.2.fill", .pink, "Circles", "Connect with accountability groups", .circles),
            ("chart.bar.fill", .orange, "Insights", "Track your progress over time", .insights),
            ("trophy.fill", .yellow, "Achievements", "Earn badges and level up", .achievements)
        ]
    }

    private func animateFeatures() {
        for (index, feature) in features.enumerated() {
            withAnimation(.easeOut(duration: 0.4).delay(0.2 + Double(index) * 0.1)) {
                _ = visibleFeatures.insert(feature.title)
            }
        }
    }
}

#Preview {
    HomeExploreStep(onComplete: {})
}
