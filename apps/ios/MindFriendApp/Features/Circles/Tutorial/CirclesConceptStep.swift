//
//  CirclesConceptStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: What are Circles?
//

import SwiftUI

/// Step 1: Introduce the Circles concept
struct CirclesConceptStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showMembers = false

    var body: some View {
        TutorialStepView(
            icon: "person.2.fill",
            iconColor: .pink,
            headline: "What Are Circles?",
            subheadline: "Small accountability groups (2-6 people) who support each other's wellness journey.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Circle visualization
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(Color.pink.opacity(0.2), lineWidth: 3)
                        .frame(width: 150, height: 150)

                    // Members
                    ForEach(0..<5, id: \.self) { i in
                        let angle = Double(i) * (2 * .pi / 5) - .pi / 2
                        let x = cos(angle) * 55
                        let y = sin(angle) * 55

                        Circle()
                            .fill(memberColors[i])
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            )
                            .offset(x: x, y: y)
                            .scaleEffect(showMembers ? 1 : 0)
                            .animation(
                                .spring(response: 0.4, dampingFraction: 0.6)
                                    .delay(0.3 + Double(i) * 0.1),
                                value: showMembers
                            )
                    }
                }
                .frame(height: 170)

                // Benefits
                VStack(alignment: .leading, spacing: 8) {
                    CircleBenefitRow(icon: "heart.fill", color: .pink, text: "Share daily check-ins")
                    CircleBenefitRow(icon: "hands.sparkles.fill", color: .purple, text: "Give and receive encouragement")
                    CircleBenefitRow(icon: "checkmark.circle.fill", color: .green, text: "Stay accountable together")
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
            }
            .onAppear { showMembers = true }
        }
    }

    private let memberColors: [Color] = [.pink, .purple, .blue, .orange, .green]
}

private struct CircleBenefitRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    CirclesConceptStep(onNext: {}, onSkip: {})
}
