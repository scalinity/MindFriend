//
//  ChatCoachingStep.swift
//  MindFriendApp
//
//  Tutorial Step 3: Cognitive coaching features
//

import SwiftUI

/// Step 3: Explain cognitive coaching and distortion detection
struct ChatCoachingStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showDistortion = false
    @State private var showReframe = false

    var body: some View {
        TutorialStepView(
            icon: "brain.head.profile",
            iconColor: SupportTheme.accent,
            headline: "Cognitive Coaching",
            subheadline: "Your companion can help identify unhelpful thought patterns and suggest healthier perspectives.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: SupportTheme.Spacing.xs) {
                // Example thought
                VStack(alignment: .leading, spacing: SupportTheme.Spacing.xs) {
                    Text("You said:")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)

                    Text("\"I always mess everything up.\"")
                        .font(.subheadline)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(SupportTheme.Spacing.s)
                        .background(SupportTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Distortion detection
                if showDistortion {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        Image(systemName: "lightbulb.fill")
                            .font(.title3)
                            .foregroundStyle(SupportTheme.Celebration.gold)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("Pattern Detected")
                                .font(.subheadline.weight(.medium))
                            Text("All-or-nothing thinking")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.accent)
                        }

                        Spacer()
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .transition(reduceMotion ? .opacity.animation(.easeInOut(duration: 0.2)) : .move(edge: .bottom).combined(with: .opacity))
                }

                // Reframe suggestion
                if showReframe {
                    HStack(spacing: SupportTheme.Spacing.s) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3)
                            .foregroundStyle(SupportTheme.accent)

                        VStack(alignment: .leading, spacing: SupportTheme.Spacing.xxs) {
                            Text("Try reframing:")
                                .font(.subheadline.weight(.medium))
                            Text("\"I made a mistake this time, but I can learn from it.\"")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(SupportTheme.Spacing.s)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .transition(reduceMotion ? .opacity.animation(.easeInOut(duration: 0.2)) : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.5)) {
                    showDistortion = true
                }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(1.2)) {
                    showReframe = true
                }
            }
        }
    }
}

#Preview {
    ChatCoachingStep(onNext: {}, onSkip: {})
}
