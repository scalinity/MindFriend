//
//  ChatQuotaStep.swift
//  MindFriendApp
//
//  Tutorial Step 4: Explain usage quotas
//

import SwiftUI

/// Step 4: Explain free tier limits and premium benefits
struct ChatQuotaStep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onComplete: () -> Void

    @State private var showComparison = false

    var body: some View {
        TutorialStepView(
            icon: "bubble.left.and.text.bubble.right.fill",
            iconColor: SupportTheme.accent,
            headline: "Usage & Quotas",
            subheadline: "You get daily messages included. Premium unlocks unlimited conversations.",
            primaryLabel: "Start Chatting",
            primaryAction: onComplete
        ) {
            VStack(spacing: SupportTheme.Spacing.m) {
                // Free vs Premium comparison
                HStack(spacing: SupportTheme.Spacing.s) {
                    // Free tier
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        Text("Free")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SupportTheme.textSecondary)

                        VStack(spacing: SupportTheme.Spacing.xs) {
                            Text("30")
                                .font(.title.bold())
                            Text("messages/day")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                                .fixedSize()
                        }

                        VStack(spacing: SupportTheme.Spacing.xxs) {
                            FeatureCheck(text: "Text chat", included: true)
                            FeatureCheck(text: "Voice mode", included: false)
                            FeatureCheck(text: "Coaching", included: true)
                        }
                    }
                    .padding(SupportTheme.Spacing.s)
                    .frame(maxWidth: .infinity)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .opacity(showComparison ? 1 : 0)
                    .offset(x: reduceMotion ? 0 : (showComparison ? 0 : -20))

                    // Premium tier
                    VStack(spacing: SupportTheme.Spacing.xs) {
                        HStack(spacing: SupportTheme.Spacing.xxs) {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.accent)
                            Text("Premium")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SupportTheme.accent)
                        }

                        VStack(spacing: SupportTheme.Spacing.xs) {
                            Image(systemName: "infinity")
                                .font(.title.bold())
                                .foregroundStyle(SupportTheme.accent)
                            Text("unlimited")
                                .font(.caption)
                                .foregroundStyle(SupportTheme.textSecondary)
                        }

                        VStack(spacing: SupportTheme.Spacing.xxs) {
                            FeatureCheck(text: "Text chat", included: true)
                            FeatureCheck(text: "Voice mode", included: true)
                            FeatureCheck(text: "Coaching", included: true)
                        }
                    }
                    .padding(SupportTheme.Spacing.s)
                    .frame(maxWidth: .infinity)
                    .background(SupportTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                            .strokeBorder(SupportTheme.accent.opacity(0.3), lineWidth: 1)
                    )
                    .opacity(showComparison ? 1 : 0)
                    .offset(x: reduceMotion ? 0 : (showComparison ? 0 : 20))
                }
                .padding(.horizontal, SupportTheme.Spacing.l)

                // Reassurance
                Text("Your free messages refresh daily. That's plenty to get started!")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.l)
                    .opacity(showComparison ? 1 : 0)
            }
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5).delay(0.3)) {
                    showComparison = true
                }
            }
        }
    }
}

// MARK: - Feature Check Row

private struct FeatureCheck: View {
    let text: String
    let included: Bool

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: included ? "checkmark" : "xmark")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(included ? SupportTheme.accent : SupportTheme.textSecondary)

            Text(text)
                .font(.caption)
                .foregroundStyle(included ? SupportTheme.textPrimary : SupportTheme.textSecondary)
                .fixedSize()
        }
    }
}

#Preview {
    ChatQuotaStep(onComplete: {})
}
