//
//  BreakthroughCelebrationView.swift
//  MindFriendApp
//
//  Celebratory animation when breakthrough detected
//

import SwiftUI

struct BreakthroughCelebrationView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isAnimating = false

    let breakthroughSecond: Int?
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Background overlay
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                    onDismiss()
                }

            // Confetti particles
            ForEach(0..<50) { index in
                BreakthroughConfettiParticle(index: index, isAnimating: $isAnimating)
            }

            // Celebration card
            VStack(spacing: 24) {
                // Sparkles icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isAnimating)

                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(isAnimating ? 360 : 0))
                        .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: isAnimating)
                }

                // Title
                Text("Breakthrough!")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.primary)

                // Message
                VStack(spacing: 8) {
                    Text("You just experienced a significant emotional shift!")
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    if let second = breakthroughSecond {
                        Text("Detected at \(formatTime(second))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Dismiss button
                Button(action: {
                    dismiss()
                    onDismiss()
                }) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [.purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
            )
            .padding(.horizontal, 32)
            .scaleEffect(isAnimating ? 1.0 : 0.8)
            .opacity(isAnimating ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isAnimating = true
            }

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

// MARK: - Confetti Particle

struct BreakthroughConfettiParticle: View {
    let index: Int
    @Binding var isAnimating: Bool

    // Random properties for each particle
    private let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
    private let size = CGFloat.random(in: 8...16)
    private let startX = CGFloat.random(in: -UIScreen.main.bounds.width/2...UIScreen.main.bounds.width/2)
    private let startY = -CGFloat.random(in: 100...300)
    private let duration = Double.random(in: 2...4)
    private let delay = Double.random(in: 0...0.5)

    @State private var yOffset: CGFloat = 0
    @State private var xOffset: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var opacity: Double = 1

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4)
            .fill(colors[index % colors.count])
            .frame(width: size, height: size)
            .offset(x: startX + xOffset, y: startY + yOffset)
            .rotationEffect(.degrees(rotation))
            .opacity(opacity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: duration)) {
                        yOffset = UIScreen.main.bounds.height + 200
                        xOffset = CGFloat.random(in: -100...100)
                        rotation = Double.random(in: 0...720)
                        opacity = 0
                    }
                }
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
