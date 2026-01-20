//
//  QuestArcMilestoneView.swift
//  MindFriendApp
//
//  Celebration view shown when user reaches an arc milestone
//

import SwiftUI

struct QuestArcMilestoneView: View {
    let arcTitle: String
    let milestoneNumber: Int
    let totalMilestones: Int
    let dayNumber: Int
    let onDismiss: () -> Void
    let onShare: () -> Void

    @State private var showConfetti = false
    @State private var starScale: CGFloat = 0.5
    @State private var starRotation: Double = -30

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.orange.opacity(0.3), .yellow.opacity(0.2), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Content
            VStack(spacing: 32) {
                Spacer()

                // Animated star badge
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(Color.yellow.opacity(0.3))
                        .frame(width: 160, height: 160)
                        .blur(radius: 20)

                    // Star
                    Image(systemName: "star.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(starScale)
                        .rotationEffect(.degrees(starRotation))

                    // Milestone number
                    Text("\(milestoneNumber)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 12) {
                    Text("Milestone Reached!")
                        .font(.largeTitle.weight(.bold))

                    Text("Day \(dayNumber) of \(arcTitle)")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text("Milestone \(milestoneNumber) of \(totalMilestones)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)

                // Encouragement message
                Text(encouragementMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                // Actions
                VStack(spacing: 12) {
                    Button {
                        onShare()
                    } label: {
                        Label("Share with Circles", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onDismiss()
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }

            // Confetti overlay
            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                starScale = 1.0
                starRotation = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showConfetti = true
            }
        }
    }

    private var encouragementMessage: String {
        switch milestoneNumber {
        case 1:
            return "You've taken the first big step! Keep the momentum going."
        case 2:
            return "Halfway through your journey. You're building real habits!"
        case 3:
            return "Almost there! Your dedication is truly inspiring."
        default:
            if milestoneNumber == totalMilestones {
                return "You did it! You've completed the entire journey!"
            }
            return "Amazing progress! Keep up the great work."
        }
    }
}

// MARK: - Confetti View

private struct ConfettiView: View {
    @State private var particles: [ConfettiParticle] = []

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                for particle in particles {
                    let age = timeline.date.timeIntervalSince(particle.createdAt)
                    let progress = min(age / particle.lifetime, 1.0)

                    if progress < 1.0 {
                        let x = particle.startX + particle.velocityX * age
                        let y = particle.startY + particle.velocityY * age + 200 * age * age
                        let rotation = particle.rotation + particle.rotationSpeed * age
                        let opacity = 1.0 - progress

                        var contextCopy = context
                        contextCopy.opacity = opacity
                        contextCopy.translateBy(x: x, y: y)
                        contextCopy.rotate(by: .degrees(rotation))

                        let rect = CGRect(x: -4, y: -4, width: 8, height: 8)
                        contextCopy.fill(
                            Path(ellipseIn: rect),
                            with: .color(particle.color)
                        )
                    }
                }
            }
        }
        .onAppear {
            generateParticles()
        }
    }

    private func generateParticles() {
        let colors: [Color] = [.yellow, .orange, .red, .pink, .purple, .blue, .green]
        var newParticles: [ConfettiParticle] = []

        for _ in 0..<50 {
            newParticles.append(ConfettiParticle(
                startX: CGFloat.random(in: 50...350),
                startY: CGFloat.random(in: -50...0),
                velocityX: CGFloat.random(in: -50...50),
                velocityY: CGFloat.random(in: 50...150),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -180...180),
                color: colors.randomElement()!,
                lifetime: Double.random(in: 2...4),
                createdAt: Date()
            ))
        }

        particles = newParticles
    }
}

private struct ConfettiParticle {
    let startX: CGFloat
    let startY: CGFloat
    let velocityX: CGFloat
    let velocityY: CGFloat
    let rotation: Double
    let rotationSpeed: Double
    let color: Color
    let lifetime: Double
    let createdAt: Date
}

// MARK: - Arc Completion View

struct QuestArcCompletionView: View {
    let arcTitle: String
    let totalDays: Int
    let totalMilestones: Int
    let onDismiss: () -> Void
    let onBrowseMore: () -> Void

    @State private var trophyScale: CGFloat = 0.5
    @State private var showConfetti = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.purple.opacity(0.3), .blue.opacity(0.2), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Trophy
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 180, height: 180)
                        .blur(radius: 25)

                    Image(systemName: "trophy.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.yellow, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(trophyScale)
                }

                VStack(spacing: 12) {
                    Text("Journey Complete!")
                        .font(.largeTitle.weight(.bold))

                    Text(arcTitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // Stats
                HStack(spacing: 32) {
                    VStack {
                        Text("\(totalDays)")
                            .font(.title.weight(.bold))
                        Text("Days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack {
                        Text("\(totalMilestones)")
                            .font(.title.weight(.bold))
                        Text("Milestones")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("Congratulations on completing your wellness journey! You've built lasting habits and shown incredible dedication.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        onBrowseMore()
                    } label: {
                        Label("Start Another Journey", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }

            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.5)) {
                trophyScale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showConfetti = true
            }
        }
    }
}

#Preview("Milestone") {
    QuestArcMilestoneView(
        arcTitle: "Stress Relief Journey",
        milestoneNumber: 1,
        totalMilestones: 3,
        dayNumber: 3,
        onDismiss: {},
        onShare: {}
    )
}

#Preview("Completion") {
    QuestArcCompletionView(
        arcTitle: "Stress Relief Journey",
        totalDays: 14,
        totalMilestones: 3,
        onDismiss: {},
        onBrowseMore: {}
    )
}
