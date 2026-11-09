//
//  BreakthroughCelebrationView.swift
//  MindFriendApp
//
//  Celebratory animation when breakthrough detected
//

import SwiftUI

struct BreakthroughCelebrationView: View {
    @Environment(\.dismiss) private var dismiss

    let breakthroughSecond: Int?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Background overlay
            SupportTheme.canvas.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                    onDismiss()
                }

            CelebrationParticles().ignoresSafeArea()

            // Celebration card
            VStack(spacing: SupportTheme.Spacing.l) {
                CelebrationEmblem(.symbol("sparkles"))
                    .celebrationReveal()

                // Title
                Text("A moment of change")
                    .font(.system(.largeTitle).weight(.bold))
                    .foregroundColor(SupportTheme.textPrimary)

                // Message
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text("You experienced a meaningful emotional shift.")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if let second = breakthroughSecond {
                        Text("Detected at \(formatTime(second))")
                            .font(.subheadline)
                            .foregroundColor(SupportTheme.textSecondary)
                    }
                }

                Button("Continue") {
                    dismiss()
                    onDismiss()
                }
                .buttonStyle(.supportPrimary)
            }
            .supportCard()
            .padding(.horizontal, SupportTheme.Spacing.xl)
            .celebrationReveal()
        }
        .onAppear {
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                dismiss()
                onDismiss()
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

// MARK: - Preview

#Preview {
    BreakthroughCelebrationView(
        breakthroughSecond: 47,
        onDismiss: {}
    )
}
