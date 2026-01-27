import SwiftUI
import UIKit

// MARK: - Feature Unlock View

/// A celebration view shown when a user unlocks new features through activation.
/// Displays a congratulatory message, lists unlocked features, and includes celebration animations.
struct FeatureUnlockView: View {
    let unlockedFeatures: [ActivationService.Feature]
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var showFeatures = false
    @State private var showButton = false
    @State private var particleOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.2),
                    Color(red: 0.15, green: 0.1, blue: 0.25),
                    Color(red: 0.1, green: 0.1, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Celebration particles
            CelebrationParticles(opacity: particleOpacity)

            // Main content
            VStack(spacing: 32) {
                Spacer()

                // Unlock icon with glow
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.blue.opacity(0.4), .clear],
                                center: .center,
                                startRadius: 40,
                                endRadius: 100
                            )
                        )
                        .frame(width: 200, height: 200)
                        .blur(radius: 20)

                    // Icon background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: .blue.opacity(0.5), radius: 20, x: 0, y: 10)

                    // Unlock icon
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundStyle(.white)
                }
                .scaleEffect(showContent ? 1 : 0.5)
                .opacity(showContent ? 1 : 0)

                // Congratulations text
                VStack(spacing: 12) {
                    Text("Congratulations!")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    Text("You've unlocked new features")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)

                Spacer()

                // Unlocked features list
                VStack(spacing: 16) {
                    ForEach(unlockedFeatures.indices, id: \.self) { index in
                        let feature = unlockedFeatures[index]
                        UnlockedFeatureRow(feature: feature)
                            .opacity(showFeatures ? 1 : 0)
                            .offset(x: showFeatures ? 0 : -50)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.7)
                                    .delay(Double(index) * 0.15),
                                value: showFeatures
                            )
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Continue button
                Button(action: onDismiss) {
                    Text("Let's Go!")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(16)
                        .shadow(color: .blue.opacity(0.4), radius: 15, x: 0, y: 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 30)
            }
        }
        .onAppear {
            // Staggered animation sequence
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                showContent = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation {
                    showFeatures = true
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    showButton = true
                }
            }

            // Fade out particles after a while
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 1.0)) {
                    particleOpacity = 0.3
                }
            }
        }
    }
}

// MARK: - Unlocked Feature Row

private struct UnlockedFeatureRow: View {
    let feature: ActivationService.Feature

    var body: some View {
        HStack(spacing: 16) {
            // Checkmark icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
            }

            // Feature info
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.displayName)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(featureDescription)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer()

            // Tab icon
            Image(systemName: tabIcon)
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }

    private var featureDescription: String {
        switch feature {
        case .programs:
            return "Guided exercises and wellness programs"
        case .outcomes:
            return "Track your progress and insights"
        default:
            return ""
        }
    }

    private var tabIcon: String {
        switch feature {
        case .home: return "house.fill"
        case .chat: return "bubble.left.fill"
        case .profile: return "person.fill"
        case .programs: return "book.fill"
        case .outcomes: return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Celebration Particles

private struct CelebrationParticles: View {
    let opacity: Double

    @State private var particles: [CelebrationParticleData] = []
    @State private var viewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ForEach(particles) { particle in
                Circle()
                    .fill(particle.color)
                    .frame(width: particle.size, height: particle.size)
                    .position(particle.position)
                    .opacity(particle.opacity * opacity)
            }
            .onAppear {
                viewSize = geometry.size
                generateParticles(in: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                viewSize = newSize
                generateParticles(in: newSize)
            }
        }
    }

    private func generateParticles(in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        particles = (0..<30).map { _ in
            CelebrationParticleData(
                position: CGPoint(
                    x: CGFloat.random(in: 0...size.width),
                    y: CGFloat.random(in: 0...size.height)
                ),
                color: [Color.blue, .purple, .pink, .cyan, .white].randomElement()!.opacity(0.6),
                size: CGFloat.random(in: 4...12),
                opacity: Double.random(in: 0.3...0.8)
            )
        }

        // Animate particles
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
            particles = particles.map { particle in
                var newParticle = particle
                newParticle.position.y += CGFloat.random(in: -50...50)
                newParticle.position.x += CGFloat.random(in: -30...30)
                return newParticle
            }
        }
    }
}

private struct CelebrationParticleData: Identifiable {
    let id = UUID()
    var position: CGPoint
    let color: Color
    let size: CGFloat
    let opacity: Double
}

// MARK: - Preview

#Preview("Feature Unlock") {
    FeatureUnlockView(
        unlockedFeatures: [.programs, .outcomes],
        onDismiss: {}
    )
}
