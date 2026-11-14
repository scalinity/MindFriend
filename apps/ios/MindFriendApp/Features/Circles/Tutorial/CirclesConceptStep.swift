//
//  CirclesConceptStep.swift
//  MindFriendApp
//
//  Tutorial Step 1: What are Circles?
//

import SwiftUI

/// Step 1: Introduce the Circles concept
struct CirclesConceptStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showMembers = false

    var body: some View {
        TutorialStepView(
            icon: "person.2.fill",
            iconColor: SupportTheme.Area.people.palette.ink,
            headline: "What Are Circles?",
            subheadline: "Small accountability groups (2-6 people) who support each other's wellness journey.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Circle visualization
                ZStack {
                    // Background circle
                    Circle()
                        .stroke(SupportTheme.Area.people.palette.ink.opacity(0.2), lineWidth: 3)
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
                                    .foregroundStyle(SupportTheme.onAccent)
                            )
                            .offset(x: x, y: y)
                            .scaleEffect(reduceMotion ? 1 : (showMembers ? 1 : 0))
                            .opacity(showMembers ? 1 : 0)
                            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.6)
                                    .delay(0.3 + Double(i) * 0.1),
                                value: showMembers
                            )
                    }
                }
                .frame(height: 170)

                // Benefits
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    CircleBenefitRow(icon: "heart.fill", color: SupportTheme.Area.people.palette.ink, text: "Share daily check-ins")
                    CircleBenefitRow(icon: "hands.sparkles.fill", color: SupportTheme.Area.journal.palette.ink, text: "Give and receive encouragement")
                    CircleBenefitRow(icon: "checkmark.circle.fill", color: SupportTheme.Status.positive, text: "Stay accountable together")
                }
                .padding(SupportTheme.Spacing.s)
                .background(SupportTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                .padding(.horizontal, SupportTheme.Spacing.l)
            }
            .onAppear { showMembers = true }
        }
    }

    private let memberColors: [Color] = [
        SupportTheme.Area.people.palette.ink, SupportTheme.Area.journal.palette.ink, SupportTheme.Area.voice.palette.ink,
        SupportTheme.Area.quests.palette.ink, SupportTheme.Status.positive
    ]
}

private struct CircleBenefitRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(minWidth: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    CirclesConceptStep(onNext: {}, onSkip: {})
}
