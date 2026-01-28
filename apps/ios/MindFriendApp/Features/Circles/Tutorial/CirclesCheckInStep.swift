//
//  CirclesCheckInStep.swift
//  MindFriendApp
//
//  Tutorial Step 2: Daily check-ins
//

import SwiftUI

/// Step 2: Explain daily check-in flow
struct CirclesCheckInStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void

    @State private var showCheckIn = false
    @State private var showReactions = false

    var body: some View {
        TutorialStepView(
            icon: "hand.wave.fill",
            iconColor: .orange,
            headline: "Daily Check-ins",
            subheadline: "Share how you're doing with your circle. Quick, simple, and supportive.",
            primaryAction: onNext,
            skipAction: onSkip
        ) {
            VStack(spacing: 16) {
                // Example check-in
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundStyle(.white)
                            )

                        VStack(alignment: .leading) {
                            Text("Sarah")
                                .font(.subheadline.weight(.medium))
                            Text("Today at 9:30 AM")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Check-in content
                    Text("Feeling good today! Started with a morning walk and ready to tackle the day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Reactions
                    if showReactions {
                        HStack(spacing: 8) {
                            ReactionPill(emoji: "heart.fill", count: 3, color: .pink)
                            ReactionPill(emoji: "hand.thumbsup.fill", count: 2, color: .blue)
                            ReactionPill(emoji: "sparkles", count: 1, color: .orange)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .scaleEffect(showCheckIn ? 1 : 0.95)
                .opacity(showCheckIn ? 1 : 0)
                .padding(.horizontal, 24)

                // Info
                VStack(spacing: 6) {
                    Text("React to show support")
                        .font(.caption.weight(.medium))
                    Text("Hugs, high-fives, and encouragement make a difference")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .opacity(showReactions ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                    showCheckIn = true
                }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(1.0)) {
                    showReactions = true
                }
            }
        }
    }
}

private struct ReactionPill: View {
    let emoji: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: emoji)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    CirclesCheckInStep(onNext: {}, onSkip: {})
}
