//
//  JourneyConceptStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: Introduces what Quest Journeys are
//

import SwiftUI

/// Step 1: Explain the core journey concept
struct JourneyConceptStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showCategories = false

    private let categories = [
        ("brain.head.profile", "Stress", Color.blue),
        ("moon.zzz.fill", "Sleep", Color.indigo),
        ("figure.stand", "Confidence", Color.purple),
        ("target", "Focus", Color.green),
        ("heart.fill", "Resilience", Color.pink)
    ]

    var body: some View {
        JourneyTutorialStepLayout(
            icon: "map.fill",
            iconColor: .blue,
            headline: "Your Personal Growth Journey",
            subheadline: "Multi-day guided programs designed to build lasting habits and skills.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 20) {
                // Journey categories
                HStack(spacing: 16) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                        VStack(spacing: 8) {
                            Image(systemName: category.0)
                                .font(.title2)
                                .foregroundStyle(category.2)
                                .frame(width: 44, height: 44)
                                .background(category.2.opacity(0.15))
                                .clipShape(Circle())
                                .scaleEffect(showCategories ? 1.0 : 0.5)
                                .opacity(showCategories ? 1.0 : 0.0)

                            Text(category.1)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .opacity(showCategories ? 1.0 : 0.0)
                        }
                        .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.1), value: showCategories)
                    }
                }
                .padding(.horizontal)

                // Explanation
                Text("Each journey focuses on a specific area, guiding you through **daily activities** that compound into real transformation.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            .onAppear {
                withAnimation {
                    showCategories = true
                }
            }
        }
    }
}

#Preview {
    JourneyConceptStep(onNext: {}, onSkip: {})
}
