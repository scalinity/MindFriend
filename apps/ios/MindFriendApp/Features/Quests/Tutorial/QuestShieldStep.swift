//
//  QuestShieldStep.swift
//  MindFriendApp
//
//  Tutorial Step 4: Explain streak shields (premium feature)
//

import SwiftUI

/// Step 4: Show how streak shields protect your progress
struct QuestShieldStep: View {
    let onComplete: () -> Void

    @State private var showShield = false
    @State private var shieldActive = false

    var body: some View {
        TutorialStepView(
            icon: "shield.fill",
            iconColor: .blue,
            headline: "Streak Shields",
            subheadline: "Life happens. Shields protect your streak when you can't complete a quest.",
            primaryLabel: "Start Your Journey",
            primaryAction: onComplete
        ) {
            VStack(spacing: 20) {
                // Shield animation
                ZStack {
                    // Background glow
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .scaleEffect(shieldActive ? 1.2 : 1.0)
                        .opacity(shieldActive ? 0.5 : 0)

                    // Shield icon
                    Image(systemName: "shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(showShield ? 1.0 : 0.5)
                        .opacity(showShield ? 1 : 0)

                    // Checkmark overlay
                    if shieldActive {
                        Image(systemName: "checkmark")
                            .font(.title.weight(.bold))
                            .foregroundStyle(.white)
                            .offset(y: 5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                // Shield info
                VStack(spacing: 12) {
                    HStack(spacing: 16) {
                        shieldFeature(icon: "calendar.badge.clock", text: "Skip a day without losing your streak")
                        shieldFeature(icon: "crown.fill", text: "Premium members get shields monthly")
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .opacity(showShield ? 1 : 0)

                // Tip
                Text("Don't worry - you'll build up shields as you maintain your streak!")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .opacity(shieldActive ? 1 : 0)
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5).delay(0.3)) {
                    showShield = true
                }
                withAnimation(.easeInOut(duration: 0.6).delay(1.0).repeatForever(autoreverses: true)) {
                    shieldActive = true
                }
            }
        }
    }

    private func shieldFeature(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    QuestShieldStep(onComplete: {})
}
