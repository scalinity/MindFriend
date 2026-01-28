//
//  ChatQuotaStep.swift
//  MindFriendApp
//
//  Tutorial Step 4: Explain usage quotas
//

import SwiftUI

/// Step 4: Explain free tier limits and premium benefits
struct ChatQuotaStep: View {
    let onComplete: () -> Void

    @State private var showComparison = false

    var body: some View {
        TutorialStepView(
            icon: "bubble.left.and.text.bubble.right.fill",
            iconColor: .green,
            headline: "Usage & Quotas",
            subheadline: "You get daily messages included. Premium unlocks unlimited conversations.",
            primaryLabel: "Start Chatting",
            primaryAction: onComplete
        ) {
            VStack(spacing: 20) {
                // Free vs Premium comparison
                HStack(spacing: 16) {
                    // Free tier
                    VStack(spacing: 12) {
                        Text("Free")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        VStack(spacing: 8) {
                            Text("5")
                                .font(.title.bold())
                            Text("messages/day")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 4) {
                            FeatureCheck(text: "Text chat", included: true)
                            FeatureCheck(text: "Voice mode", included: false)
                            FeatureCheck(text: "Coaching", included: true)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .opacity(showComparison ? 1 : 0)
                    .offset(x: showComparison ? 0 : -20)

                    // Premium tier
                    VStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "crown.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Premium")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                        }

                        VStack(spacing: 8) {
                            Image(systemName: "infinity")
                                .font(.title.bold())
                                .foregroundStyle(.orange)
                            Text("unlimited")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(spacing: 4) {
                            FeatureCheck(text: "Text chat", included: true)
                            FeatureCheck(text: "Voice mode", included: true)
                            FeatureCheck(text: "Coaching", included: true)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .opacity(showComparison ? 1 : 0)
                    .offset(x: showComparison ? 0 : 20)
                }
                .padding(.horizontal, 24)

                // Reassurance
                Text("Your free messages refresh daily. That's plenty to get started!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(showComparison ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
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
        HStack(spacing: 6) {
            Image(systemName: included ? "checkmark" : "xmark")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(included ? .green : .secondary)

            Text(text)
                .font(.caption)
                .foregroundStyle(included ? .primary : .secondary)
        }
    }
}

#Preview {
    ChatQuotaStep(onComplete: {})
}
